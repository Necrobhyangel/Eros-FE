import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:fehviewer/common/global.dart';
import 'package:fehviewer/common/service/depth_service.dart';
import 'package:fehviewer/models/index.dart';
import 'package:fehviewer/network/gallery_request.dart';
import 'package:fehviewer/pages/gallery/controller/gallery_page_controller.dart';
import 'package:fehviewer/store/db/dao/gallery_task_dao.dart';
import 'package:fehviewer/store/db/dao/image_task_dao.dart';
import 'package:fehviewer/store/db/database.dart';
import 'package:fehviewer/store/db/entity/gallery_image_task.dart';
import 'package:fehviewer/store/db/entity/gallery_task.dart';
import 'package:fehviewer/store/gallery_store.dart';
import 'package:fehviewer/utils/logger.dart';
import 'package:fehviewer/utils/toast.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class DownloadController extends GetxController {
  // key DownloadTaskInfo.tag
  final RxMap<String, DownloadTaskInfo> archiverTaskMap =
      <String, DownloadTaskInfo>{}.obs;

  final List<String> _archiverDlIdList = <String>[];

  final GStore _gStore = Get.find();

  Future<AppDatabase> _getDatabase() async =>
      await $FloorAppDatabase.databaseBuilder('gallery_task.db').build();
  Future<GalleryTaskDao> _getGalleryTaskDao() async =>
      (await _getDatabase()).galleryTaskDao;
  Future<ImageTaskDao> _getImageTaskDao() async =>
      (await _getDatabase()).imageTaskDao;

  Future<void> downloadArchiverFile({
    @required String gid,
    @required String dlType,
    @required String title,
    @required String url,
  }) async {
    final String _tag = '$gid$dlType';

    logger.d('$url');

    if (archiverTaskMap.containsKey(_tag)) {
      showToast('下载任务已存在');
      return;
    }

    final String _taskId = await _downloadFile(url, await _getDownloadPath());

    archiverTaskMap[_tag] = DownloadTaskInfo()
      ..tag = _tag
      ..gid = gid
      ..type = dlType
      ..taskId = _taskId
      ..title = title;

    _archiverDlIdList.add(_tag);

    showToast('下载任务已添加');
  }

  Future<void> downloadGallery({
    @required String url,
    @required int fileCount,
    @required String title,
    int gid,
    String token,
  }) async {
    GalleryTaskDao _galleryTaskDao;
    ImageTaskDao _imageTaskDao;
    try {
      _galleryTaskDao = await _getGalleryTaskDao();
      _imageTaskDao = await _getImageTaskDao();
    } catch (e, stack) {
      logger.e('$e\n$stack ');
      rethrow;
    }

    int _gid;
    String _token;
    if (gid == null || token == null) {
      final RegExpMatch _match =
          RegExp(r'/g/(\d+)/([0-9a-f]{10})/?').firstMatch(url);
      _gid = int.parse(_match.group(1));
      _token = _match.group(2);
    }

    // 先查询任务是否已存在
    final GalleryTask _oriTask =
        await _galleryTaskDao.findGalleryTaskByGid(gid);
    if (_oriTask != null) {
      logger.e('$gid 任务已存在');
      showToast('下载任务已存在');
      logger.d('${_oriTask.toString()} ');
      return;
    }

    // 登记主任务表
    final GalleryTask galleryTask = GalleryTask(
      gid: gid ?? _gid,
      token: token ?? _token,
      url: url,
      title: title,
      fileCount: fileCount,
    );
    logger.d('add task ${galleryTask.toString()}');
    try {
      _galleryTaskDao.insertTask(galleryTask);
    } catch (e, stack) {
      logger.e('$e\n$stack ');
      rethrow;
    }

    showToast('${galleryTask.gid} 下载任务已入队');

    // 翻页, 获取所有大图页的href
    final GalleryPageController _pageController = Get.find(tag: pageCtrlDepth);
    final List<GalleryPreview> _allPreview = await _getAllPreviews(
        url: url,
        fileCount: fileCount,
        initPreviews: _pageController.firstPagePreview);

    logger.d('${_allPreview.length}');

    // 插入任务明细
    final List<GalleryImageTask> _galleryImageTasks = _allPreview
        .map((GalleryPreview e) => GalleryImageTask(
              gid: galleryTask.gid,
              token: galleryTask.token,
              href: e.href,
              ser: e.ser,
            ))
        .toList();
    _imageTaskDao.insertImageTasks(_galleryImageTasks);

    final List<GalleryImageTask> _list =
        await _imageTaskDao.findAllGalleryTaskByGid(galleryTask.gid);
    logger.d('${_list.map((e) => e.toString()).join('\n')} ');
  }

  Future<List<GalleryPreview>> _getAllPreviews({
    String url,
    List<GalleryPreview> initPreviews,
    int fileCount,
  }) async {
    if (initPreviews != null &&
        initPreviews.isNotEmpty &&
        initPreviews.length == fileCount) {
      return initPreviews;
    }

    final List<GalleryPreview> _rultList = [];
    _rultList.addAll(initPreviews);
    int _curPage = 0;
    while (_rultList.length < fileCount) {
      try {
        final List<GalleryPreview> _moreGalleryPreviewList =
            await Api.getGalleryPreview(
          url,
          page: _curPage + 1,
          // cancelToken: cancelToken,
          refresh: true,
        );

        // 避免重复添加
        if (_moreGalleryPreviewList.first.ser > _rultList.last.ser) {
          logger.d('下载任务 添加图片对象 起始序号${_moreGalleryPreviewList.first.ser}  '
              '数量${_moreGalleryPreviewList.length}');
          _rultList.addAll(_moreGalleryPreviewList);
        }
        // 成功后才+1
        _curPage++;
      } catch (e, stack) {
        showToast('$e');
        logger.e('$e\n$stack');
        rethrow;
      }
    }

    return _rultList;
  }

  final ReceivePort _port = ReceivePort();

  @override
  void onInit() {
    super.onInit();

    _bindBackgroundIsolate();
    FlutterDownloader.registerCallback(_downloadCallback, stepSize: 2);

    // 从GS中初始化 archiverDlMap
    final Map<String, DownloadTaskInfo> _archivermap =
        _gStore.archiverTaskMap ?? <String, DownloadTaskInfo>{};
    archiverTaskMap(_archivermap);

    ever(archiverTaskMap, (Map<String, DownloadTaskInfo> val) {
      _gStore.archiverTaskMap = val;
    });

    // 读取所有任务
    _prepare();
  }

  @override
  void onClose() {
    _unbindBackgroundIsolate();
    super.onClose();
  }

  void _bindBackgroundIsolate() {
    final bool isSuccess = IsolateNameServer.registerPortWithName(
        _port.sendPort, 'downloader_send_port');
    if (!isSuccess) {
      _unbindBackgroundIsolate();
      _bindBackgroundIsolate();
      return;
    }

    _port.listen((dynamic data) {
      final String id = data[0];
      final DownloadTaskStatus status = data[1];
      final int progress = data[2];
      _updateItem(id, status, progress);
    });
  }

  void _unbindBackgroundIsolate() {
    IsolateNameServer.removePortNameMapping('downloader_send_port');
  }

  /// 不在 archiverDlMap 中的任务
  Future<void> _prepare() async {
    final List<DownloadTask> tasks = await FlutterDownloader.loadTasks();
    logger.d(
        'loadTasks \n${tasks.map((DownloadTask e) => e.toString().split(', ').join('\n')).join('\n----------\n')} ');

    for (final DownloadTask downloadTask in tasks) {
      final int _index = archiverTaskMap.entries.toList().indexWhere(
          (MapEntry<String, DownloadTaskInfo> element) =>
              element.value.taskId == downloadTask.taskId);

      // 不在 archiverTaskMap 中的任务 直接删除
      if (_index < 0) {
        logger.d(
            'remove task \n${downloadTask.toString().split(', ').join('\n')}');
        FlutterDownloader.remove(
            taskId: downloadTask.taskId, shouldDeleteContent: true);
      } else {
        // 否则更新
        final DownloadTaskInfo _taskInfo = archiverTaskMap.entries
            .firstWhere((MapEntry<String, DownloadTaskInfo> element) =>
                element.value.taskId == downloadTask.taskId)
            .value;

        // 触发ever 保存到GS中
        archiverTaskMap[_taskInfo.tag] = _taskInfo
          ..status = downloadTask.status.value
          ..progress = downloadTask.progress;

        update([_taskInfo.tag]);
      }
    }
  }

  /// 更新任务状态
  Future<void> _updateItem(
      String id, DownloadTaskStatus status, int progress) async {
    // 根据taskid 从数据库中 获取任务数据
    final DownloadTask _task = (await FlutterDownloader.loadTasksWithRawQuery(
            query: "SELECT * FROM task WHERE task_id='$id'"))
        .first;

    logger.d(
        'Background Isolate Callback: _task ($id) is in status ($status) and process ($progress)');

    final DownloadTaskInfo _taskInfo = archiverTaskMap.entries
        .firstWhere((MapEntry<String, DownloadTaskInfo> element) =>
            element.value.taskId == id)
        .value;

    _taskInfo
      ..progress = progress
      ..status = status.value;

    if (_task.filename != null &&
        _task.filename != 'null' &&
        _task.filename != '<null>' &&
        _task.filename.trim().isNotEmpty) {
      logger.d('${_task.filename} ');
      _taskInfo.title = _task.filename;
    }

    // 触发ever 保存到GS中
    archiverTaskMap[_taskInfo.tag] = _taskInfo;

    update([_taskInfo.tag]);
  }

  /// 获取下载路径
  Future<String> _getDownloadPath() async {
    final String _dirPath = GetPlatform.isAndroid
        ? path.join((await getExternalStorageDirectory()).path, 'Download')
        : path.join(Global.appDocPath, 'Download', 'Archiver');
    // : Global.appDocPath;

    final Directory savedDir = Directory(_dirPath);
    // 判断下载路径是否存在
    final bool hasExisted = savedDir.existsSync();
    // 不存在就新建路径
    if (!hasExisted) {
      savedDir.createSync(recursive: true);
    }

    return _dirPath;
  }

  // 根据 downloadUrl 和 savePath 下载文件
  Future<String> _downloadFile(String downloadUrl, String savePath,
      {String fileName}) async {
    return await FlutterDownloader.enqueue(
      url: downloadUrl,
      savedDir: savePath,
      fileName: fileName,
      showNotification: false,
      openFileFromNotification: false,
    );
  }
}

/// 下载进度回调顶级函数
void _downloadCallback(String id, DownloadTaskStatus status, int progress) {
  final SendPort send =
      IsolateNameServer.lookupPortByName('downloader_send_port');
  send.send([id, status, progress]);
}
