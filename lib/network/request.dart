import 'dart:io';

import 'package:collection/collection.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_http_cache/dio_http_cache.dart';
import 'package:fehviewer/common/controller/advance_search_controller.dart';
import 'package:fehviewer/common/controller/user_controller.dart';
import 'package:fehviewer/common/global.dart';
import 'package:fehviewer/common/parser/gallery_detail_parser.dart';
import 'package:fehviewer/const/const.dart';
import 'package:fehviewer/models/base/eh_models.dart';
import 'package:fehviewer/pages/gallery/controller/archiver_controller.dart';
import 'package:fehviewer/pages/tab/fetch_list.dart';
import 'package:fehviewer/utils/logger.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart' hide FormData;

import 'app_dio/pdio.dart';
import 'gallery_request.dart';

Options getCacheOptions({bool forceRefresh = false, Options? options}) {
  return buildCacheOptions(
    const Duration(days: 5),
    maxStale: const Duration(days: 7),
    forceRefresh: forceRefresh,
    options: options,
  );
}

Future<GalleryList?> getGallery({
  int? page,
  String? fromGid,
  String? serach,
  int? cats,
  bool refresh = false,
  CancelToken? cancelToken,
  GalleryListType? galleryListType,
  String? toplist,
  String? favcat,
  ValueChanged<List<Favcat>>? favCatList,
}) async {
  final AdvanceSearchController _searchController = Get.find();
  DioHttpClient dioHttpClient = DioHttpClient(dioConfig: ehDioConfig);

  await checkCookie();

  logger.v('df ${ehDioConfig}');

  late final String _url;
  switch (galleryListType) {
    case GalleryListType.watched:
      _url = '/watched';
      break;
    case GalleryListType.toplist:
      _url = '${EHConst.EH_BASE_URL}/toplist.php';
      break;
    case GalleryListType.favorite:
      _url = '/favorites.php';
      break;
    case GalleryListType.popular:
      _url = '/popular';
      break;
    default:
      _url = '/';
  }

  final isTopList = galleryListType == GalleryListType.toplist;
  final isFav = galleryListType == GalleryListType.favorite;
  final isPopular = galleryListType == GalleryListType.popular;

  final Map<String, dynamic> _params = <String, dynamic>{
    if (!isTopList && !isPopular) 'page': page ?? 0,
    if (isTopList) 'p': page ?? 0,
    if (!isTopList && !isPopular && !isFav) 'f_cats': cats,
    if (!isTopList && !isPopular && fromGid != null) 'from': fromGid,
    if (!isTopList && !isPopular && serach != null) 'f_search': serach,
    if (isTopList && toplist != null && toplist.isNotEmpty) 'tl': toplist,
    if (isFav && favcat != null && favcat != 'a' && favcat.isNotEmpty)
      'favcat': favcat,
  };

  /// 高级搜索处理
  if (!isTopList && !isPopular && !isFav && _searchController.enableAdvance) {
    _params['advsearch'] = 1;
    _params.addAll(_searchController.advanceSearchMap);
  }

  if (serach != null && isFav) {
    _params.addAll(_searchController.favSearchMap);
  }

  logger.d('${_params}');

  DioHttpResponse httpResponse = await dioHttpClient.get(
    _url,
    queryParameters: _params,
    httpTransformer:
        isFav ? FavoriteListHttpTransformer() : GalleryListHttpTransformer(),
    options: getCacheOptions(forceRefresh: refresh),
    cancelToken: cancelToken,
  );

  if (httpResponse.error is ListDisplayModeException) {
    logger.d(' inline_set dml');
    _params['inline_set'] = 'dm_l';

    httpResponse = await dioHttpClient.get(
      _url,
      queryParameters: _params,
      httpTransformer:
          isFav ? FavoriteListHttpTransformer() : GalleryListHttpTransformer(),
      options: getCacheOptions(forceRefresh: true),
      cancelToken: cancelToken,
    );
  }

  if (httpResponse.error is FavOrderException) {
    final _order = (httpResponse.error as FavOrderException).order;
    _params['inline_set'] = _order;
    _params.removeWhere((key, value) => key == 'page');
    httpResponse = await dioHttpClient.get(
      _url,
      queryParameters: _params,
      httpTransformer:
          isFav ? FavoriteListHttpTransformer() : GalleryListHttpTransformer(),
      options: getCacheOptions(forceRefresh: true),
      cancelToken: cancelToken,
    );
  }

  if (httpResponse.ok && httpResponse.data is GalleryList) {
    return httpResponse.data as GalleryList;
  }
}

Future checkCookie() async {
  final PersistCookieJar cookieJar = await Api.cookieJar;
  final List<Cookie> cookies =
      await cookieJar.loadForRequest(Uri.parse(Api.getBaseUrl()));
  cookies.add(Cookie('nw', '1'));

  if (cookies.firstWhereOrNull((_cookie) => _cookie.name == 'ipb_member_id') ==
      null) {
    logger.d('reset cookie');
    final user = Get.find<UserController>().user.value;
    if (user.memberId?.isNotEmpty ?? false) {
      cookies.add(Cookie('ipb_member_id', user.memberId!));
    }
    if (user.passHash?.isNotEmpty ?? false) {
      cookies.add(Cookie('ipb_pass_hash', user.passHash!));
    }
    if (user.igneous?.isNotEmpty ?? false) {
      cookies.add(Cookie('igneous', user.igneous!));
    }
  }

  cookieJar.saveFromResponse(Uri.parse(Api.getBaseUrl()), cookies);
}

Future<GalleryItem?> getGalleryDetail({
  required String url,
  bool refresh = false,
  CancelToken? cancelToken,
}) async {
  await checkCookie();

  DioHttpClient dioHttpClient = DioHttpClient(dioConfig: ehDioConfig);
  DioHttpResponse httpResponse = await dioHttpClient.get(
    url,
    httpTransformer: GalleryHttpTransformer(),
    options: getCacheOptions(forceRefresh: refresh),
    cancelToken: cancelToken,
  );
  logger.v('httpResponse.ok ${httpResponse.ok}');
  if (httpResponse.ok && httpResponse.data is GalleryItem) {
    return httpResponse.data as GalleryItem;
  } else {
    // logger.e('${httpResponse.error}');
    if (httpResponse.error?.code == 404) {
      final errMsg = parseErrGallery(httpResponse.error?.data as String? ?? '');
      logger.d('errMsg: $errMsg');
      throw BadRequestException(
          code: httpResponse.error?.code, message: errMsg);
    }
    throw httpResponse.error ?? UnknownException();
  }
}

Future<GalleryImage?> fetchImageInfo(
  String href, {
  bool refresh = false,
  String? sourceId,
  CancelToken? cancelToken,
}) async {
  final Map<String, dynamic> _params = {
    if (sourceId != null && sourceId.trim().isNotEmpty) 'nl': sourceId,
  };

  DioHttpClient dioHttpClient = DioHttpClient(dioConfig: ehDioConfig);
  DioHttpResponse httpResponse = await dioHttpClient.get(
    href,
    queryParameters: _params,
    httpTransformer: GalleryImageHttpTransformer(),
    options: getCacheOptions(forceRefresh: refresh),
    cancelToken: cancelToken,
  );

  if (httpResponse.ok && httpResponse.data is GalleryImage) {
    return (httpResponse.data as GalleryImage).copyWith(href: href);
  }
}

Future<List<GalleryImage>> getGalleryImage(
  String inUrl, {
  int? page,
  bool refresh = false,
  CancelToken? cancelToken,
}) async {
  final Map<String, dynamic> _params = {
    if (page != null) 'p': page,
  };
  DioHttpClient dioHttpClient = DioHttpClient(dioConfig: ehDioConfig);

  DioHttpResponse httpResponse = await dioHttpClient.get(
    inUrl,
    queryParameters: _params,
    httpTransformer: GalleryImageListHttpTransformer(),
    options: getCacheOptions(forceRefresh: refresh),
    cancelToken: cancelToken,
  );

  if (httpResponse.ok && httpResponse.data is List<GalleryImage>) {
    return httpResponse.data as List<GalleryImage>;
  } else {
    return [];
  }
}

Future<ArchiverProvider> getArchiver(
  String url, {
  bool refresh = true,
}) async {
  DioHttpClient dioHttpClient = DioHttpClient(dioConfig: ehDioConfig);

  DioHttpResponse httpResponse = await dioHttpClient.get(
    url,
    httpTransformer: GalleryArchiverHttpTransformer(),
    options: getCacheOptions(forceRefresh: refresh),
  );

  if (httpResponse.ok && httpResponse.data is ArchiverProvider) {
    return httpResponse.data as ArchiverProvider;
  } else {
    return ArchiverProvider();
  }
}

Future<String> postArchiverRemoteDownload(
  String url,
  String resolution,
) async {
  DioHttpClient dioHttpClient = DioHttpClient(dioConfig: ehDioConfig);

  final formData = FormData.fromMap({
    'hathdl_xres': resolution.trim(),
  });

  DioHttpResponse httpResponse = await dioHttpClient.post(
    url,
    data: formData,
    httpTransformer: GalleryArchiverRemoteDownloadResponseTransformer(),
    options: getCacheOptions(forceRefresh: true),
  );

  if (httpResponse.ok && httpResponse.data is String) {
    return httpResponse.data as String;
  } else {
    return '';
  }
}

Future<String> postArchiverLocalDownload(
  String url, {
  String? dltype,
  String? dlcheck,
}) async {
  final formData = FormData.fromMap({
    if (dltype != null) 'dltype': dltype.trim(),
    if (dlcheck != null) 'dlcheck': dlcheck.trim(),
  });
  DioHttpClient dioHttpClient = DioHttpClient(dioConfig: ehDioConfig);

  DioHttpResponse httpResponse = await dioHttpClient.post(
    url,
    data: formData,
    httpTransformer: GalleryArchiverLocalDownloadResponseTransformer(),
    options: getCacheOptions(forceRefresh: true),
  );

  if (httpResponse.ok && httpResponse.data is String) {
    return httpResponse.data as String;
  } else {
    return '';
  }
}

Future<EhSettings?> getUconfig(String url, {bool refresh = false}) async {
  await checkCookie();
  DioHttpClient dioHttpClient = DioHttpClient(dioConfig: ehDioConfig);

  DioHttpResponse httpResponse = await dioHttpClient.get(
    url,
    httpTransformer: UconfigHttpTransformer(),
    options: getCacheOptions(forceRefresh: refresh),
  );

  if (httpResponse.ok && httpResponse.data is EhSettings) {
    return httpResponse.data as EhSettings;
  }
}
