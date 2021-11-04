import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:fehviewer/common/service/ehconfig_service.dart';
import 'package:fehviewer/const/const.dart';
import 'package:fehviewer/extension.dart';
import 'package:fehviewer/store/floor/dao/tag_translat_dao.dart';
import 'package:fehviewer/store/floor/entity/tag_translat.dart';
import 'package:fehviewer/utils/dio_util.dart';
import 'package:fehviewer/utils/logger.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as path;

import '../global.dart';

const String kUrl = '/repos/EhTagTranslation/Database/releases/latest';
const String kCDNurl =
    'https://cdn.jsdelivr.net/gh/EhTagTranslation/DatabaseReleases/db.raw.json.gz';
const int kConnectTimeout = 10000;
const int kReceiveTimeout = 30000;

class TagTransController extends GetxController {
  final EhConfigService ehConfigService = Get.find();

  final HttpManager _httpManager =
      HttpManager.getInstance(baseUrl: 'https://api.github.com', cache: false);

  String? _dbUrl;
  String? _remoteVer;

  Future<TagTranslatDao> _getTagTranslatDao() async {
    return (await Global.getDatabase()).tagTranslatDao;
  }

  /// 检查更新
  Future<bool> checkUpdate({bool force = false}) async {
    if (ehConfigService.enableTagTranslateCDN) {
      logger.d('use CND');
      return true;
    }

    final String urlJsonString = await _httpManager.get(kUrl) ?? '';
    final dynamic _urlJson = jsonDecode(urlJsonString);
    // 获取发布时间 作为远程版本号
    _remoteVer =
        (_urlJson != null ? _urlJson['published_at']?.trim() : '') as String;

    // 获取当前本地版本
    final String localVer = ehConfigService.tagTranslatVer.value;

    if (_remoteVer == localVer && force == false) {
      return false;
    }

    final List<dynamic> assList = _urlJson['assets'] as List<dynamic>;
    final Map<String, String> assMap = <String, String>{};
    for (final dynamic assets in assList) {
      assMap[assets['name'] as String? ?? ''] =
          assets['browser_download_url'] as String;
    }
    _dbUrl = assMap['db.raw.json.gz'] ?? '';

    logger.i(_dbUrl);
    return true;
  }

  /// 获取数据
  Future<List> _fetch() async {
    if (ehConfigService.enableTagTranslateCDN) {
      _dbUrl = kCDNurl;
    }

    if (_dbUrl == null) {
      return [];
    }

    final HttpManager httpDB = HttpManager.getInstance();
    final Options options = Options(receiveTimeout: kReceiveTimeout);
    // final String dbJson = await httpDB.get(_dbUrl, options: options) ?? '{}';

    final gzFilePath = path.join(Global.appDocPath, 'db.raw.json.gz');
    await httpDB.downLoadFile(_dbUrl!, gzFilePath);
    List<int> bytes = File(gzFilePath).readAsBytesSync();
    List<int> data = GZipDecoder().decodeBytes(bytes);
    final String dbJson = utf8.decode(data);

    final dbdataMap = jsonDecode(dbJson);
    final List listData = dbdataMap['data'] as List;

    final head = dbdataMap['head'] as Map;
    final committer = head['committer'] as Map;
    _remoteVer = committer['when'] as String;
    logger.d('CDN _remoteVer $_remoteVer');

    return listData;
  }

  /// 更新数据库数据
  Future<void> updateDB() async {
    final TagTranslatDao tagTranslatDao = await _getTagTranslatDao();

    List listData = await _fetch();
    if (listData.isEmpty) {
      return;
    }

    final List<TagTranslat> tagTranslats = <TagTranslat>[];

    for (final data in listData) {
      loggerNoStack.v('${data['namespace']}  ${data['count']}');
      final String _namespace = data['namespace'] as String;
      Map mapC = data['data'] as Map;
      mapC.forEach((key, value) {
        final String _key = key as String;
        final String _name = (value['name'] ?? '') as String;
        final String _intro = (value['intro'] ?? '') as String;
        final String _links = (value['links'] ?? '') as String;

        tagTranslats.add(TagTranslat(
            namespace: _namespace,
            key: _key,
            name: _name,
            intro: _intro,
            links: _links));
      });
    }

    loggerNoStack.v('tag中文翻译数量 ${tagTranslats.length}');

    tagTranslatDao.insertAllTagTranslats(tagTranslats);

    ehConfigService.tagTranslatVer.value = _remoteVer ?? '';
  }

  /// 获取翻译结果
  Future<String?> _getTagTransStr(String key, {String namespace = ''}) async {
    final TagTranslatDao tagTranslatDao = await _getTagTranslatDao();
    TagTranslat? tr;
    if (namespace.isNotEmpty) {
      tr = await tagTranslatDao.findTagTranslatByKey(
          key.trim(), namespace.trim());
    } else {
      final List<TagTranslat> trans =
          await tagTranslatDao.findAllTagTranslatsByKey(key);
      if (trans.isNotEmpty) {
        // trans.shuffle();
        tr = trans.last;
      }
    }

    return tr?.nameNotMD ?? key;
  }

  Future<String?> getTranTagWithNameSpase(String tag,
      {String namespace = ''}) async {
    if (tag.contains(':')) {
      final RegExp rpfx = RegExp(r'(\w+):"?([^\$]+)\$?"?');
      final RegExpMatch? rult = rpfx.firstMatch(tag.toLowerCase());
      String _nameSpase = rult?.group(1) ?? '';
      if (_nameSpase.length == 1) {
        _nameSpase = EHConst.prefixToNameSpaceMap[_nameSpase] ?? _nameSpase;
      }

      final String _tag = rult?.group(2) ?? '';
      final String _nameSpaseTran =
          EHConst.translateTagType[_nameSpase] ?? _nameSpase;
      final String _transTag =
          await _getTagTransStr(_tag, namespace: _nameSpase) ?? _tag;

      return '$_nameSpaseTran:$_transTag';
    } else {
      return await _getTagTransStr(tag.toLowerCase(), namespace: namespace);
    }
  }

  Future<String?> getTranTagWithNameSpaseSmart(String text) async {
    if (!text.trim().contains(' ')) {
      return await getTranTagWithNameSpase(text);
    }
    logger.v(text);
    final array = text.split(RegExp(r'\s+'));
    logger.v(array.map((e) => '[$e]').join(','));

    for (int i = 0; i < array.length; i++) {
      if (array[i].startsWith(RegExp(r'\w+:"?'))) {
        if (!RegExp(r'\$"?$').hasMatch(array[i])) {
          final tempArray = array.sublist(i);
          // logger.v('tempArray $tempArray');
          final offset = tempArray
              .indexWhere((element) => RegExp(r'\$"?$').hasMatch(element));
          // logger.v('offset $offset');
          for (int j = 0; j < offset; j++) {
            array[i] = '${array[i]} ${array[i + 1]}';
            array.removeAt(i + 1);
          }
        }
      }
    }

    logger.v(array.map((e) => '[$e]').join(''));

    final _translateList = [];
    for (final text in array) {
      final String? translate = await getTranTagWithNameSpase(text);
      _translateList.add(translate ?? text);
    }

    return _translateList.join('   ');
  }

  Future<String?> getTagTranslateText(String text,
      {String namespace = ''}) async {
    if (text.contains(':')) {
      final RegExp rpfx = RegExp(r'(\w):(.+)');
      final RegExpMatch? rult = rpfx.firstMatch(text.toLowerCase());
      final String pfx = rult?.group(1) ?? '';
      final String _nameSpase = EHConst.prefixToNameSpaceMap[pfx] as String;
      final String _tag = rult?.group(2) ?? '';
      final String? _transTag =
          await _getTagTransStr(_tag, namespace: _nameSpase);

      return _transTag != null ? '$pfx:$_transTag' : text;
    } else {
      return await _getTagTransStr(text.toLowerCase(), namespace: namespace);
    }
  }

  Future<TagTranslat?> getTagTranslate(String text, String namespace) async {
    final TagTranslatDao tagTranslatDao = await _getTagTranslatDao();
    final TagTranslat? _translates =
        await tagTranslatDao.findTagTranslatByKey(text, namespace);

    logger.v(_translates?.intro);
    // 查询code字段
    final qryMap = {};
    final RegExp regCode = RegExp(r'`((\w+\s+?)*\w+)`');
    final matches = regCode.allMatches(_translates?.intro ?? '');
    for (final match in matches) {
      final _ori = match.group(1);
      if (_ori != null) {
        final _translateCode = await getTagTranslateText(_ori);
        if (_translateCode != null && _translateCode != _ori) {
          qryMap[_ori] = _translateCode;
        }
      }
    }

    final _intro = _translates?.intro?.replaceAllMapped(
        regCode, (match) => ' `${qryMap[match.group(1)]}(${match.group(1)})` ');
    logger.v(_intro);

    return _translates?.copyWith(intro: _intro);
  }

  Future<List<TagTranslat>> getTagTranslatesLike(
      {String text = '', int limit = 100}) async {
    final TagTranslatDao tagTranslatDao = await _getTagTranslatDao();

    final List<TagTranslat> _translates = await tagTranslatDao
        .findTagTranslatsWithLike('%$text%', '%$text%', limit);
    return _translates;
  }
}
