import 'package:fehviewer/common/controller/cache_controller.dart';
import 'package:fehviewer/common/service/depth_service.dart';
import 'package:fehviewer/common/service/theme_service.dart';
import 'package:fehviewer/pages/gallery/bindings/gallery_page_binding.dart';
import 'package:fehviewer/pages/gallery/controller/taginfo_controller.dart';
import 'package:fehviewer/pages/gallery/view/add_tags_page.dart';
import 'package:fehviewer/pages/gallery/view/all_preview_page.dart';
import 'package:fehviewer/pages/gallery/view/comment_page.dart';
import 'package:fehviewer/pages/gallery/view/gallery_info_page.dart';
import 'package:fehviewer/pages/gallery/view/gallery_page.dart';
import 'package:fehviewer/pages/setting/about_page.dart';
import 'package:fehviewer/pages/setting/advanced_setting_page.dart';
import 'package:fehviewer/pages/setting/controller/tab_setting_controller.dart';
import 'package:fehviewer/pages/setting/custom_hosts_page.dart';
import 'package:fehviewer/pages/setting/download_setting_page.dart';
import 'package:fehviewer/pages/setting/eh_setting_page.dart';
import 'package:fehviewer/pages/setting/log_page.dart';
import 'package:fehviewer/pages/setting/search_setting_page.dart';
import 'package:fehviewer/pages/setting/security_setting_page.dart';
import 'package:fehviewer/pages/setting/tab_setting.dart';
import 'package:fehviewer/pages/tab/bindings/tabhome_binding.dart';
import 'package:fehviewer/pages/tab/controller/tabhome_controller.dart';
import 'package:fehviewer/pages/tab/view/quick_search_page.dart';
import 'package:fehviewer/pages/tab/view/search_page.dart';
import 'package:fehviewer/route/app_pages.dart';
import 'package:fehviewer/route/routes.dart';
import 'package:fehviewer/utils/logger.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:collection/collection.dart';

import 'home_page_small.dart';

class TabHomeLarge extends GetView<TabHomeController> {
  const TabHomeLarge({Key? key, this.wide = false}) : super(key: key);
  final bool wide;

  @override
  Widget build(BuildContext context) {
    logger.v('width:${context.width}');
    return Row(
      children: [
        Container(
          width: wide ? 375 : 320,
          child: Navigator(
              key: Get.nestedKey(1),
              initialRoute: EHRoutes.home,
              onGenerateRoute: (settings) {
                final GetPage? _route = AppPages.routes
                    .firstWhereOrNull((GetPage e) => e.name == settings.name);
                if (_route != null &&
                    _route.name != EHRoutes.root &&
                    _route.name != EHRoutes.home) {
                  // logger.d('_route $_route');
                  return GetPageRoute(
                    page: _route.page,
                  );
                } else {
                  return GetPageRoute(
                    page: () => TabHomeSmall(),
                  );
                }
              }),
        ),
        Expanded(
          child: Row(
            children: [
              Container(
                color: CupertinoColors.systemGrey4,
                width: 0.5,
              ),
              Expanded(
                child: Navigator(
                  key: Get.nestedKey(2),
                  onGenerateRoute: (settings) {
                    // logger.d('$settings');
                    switch (settings.name) {
                      case EHRoutes.about:
                        return GetPageRoute(
                          page: () => AboutPage(),
                          transition: Transition.fadeIn,
                        );
                      case EHRoutes.ehSetting:
                        return GetPageRoute(
                          page: () => EhSettingPage(),
                          transition: Transition.fadeIn,
                        );
                      case EHRoutes.downloadSetting:
                        return GetPageRoute(
                          page: () => DownloadSettingPage(),
                          transition: Transition.fadeIn,
                        );
                      case EHRoutes.searchSetting:
                        return GetPageRoute(
                          page: () => SearchSettingPage(),
                          transition: Transition.fadeIn,
                        );
                      case EHRoutes.quickSearch:
                        return GetPageRoute(
                          page: () => QuickSearchListPage(),
                          transition: Transition.rightToLeft,
                        );
                      case EHRoutes.advancedSetting:
                        return GetPageRoute(
                          page: () => AdvancedSettingPage(),
                          binding: BindingsBuilder(
                              () => Get.lazyPut(() => CacheController())),
                          transition: Transition.fadeIn,
                        );
                      case EHRoutes.customHosts:
                        return GetPageRoute(
                          page: () => CustomHostsPage(),
                          transition: Transition.rightToLeft,
                        );
                      case EHRoutes.logfile:
                        return GetPageRoute(
                          page: () => LogPage(),
                          transition: Transition.rightToLeft,
                        );
                      case EHRoutes.securitySetting:
                        return GetPageRoute(
                          page: () => SecuritySettingPage(),
                          transition: Transition.fadeIn,
                        );
                      case EHRoutes.galleryPage:
                        return GetPageRoute(
                          page: () => GalleryMainPage(),
                          transition: Transition.fadeIn,
                          binding: GalleryBinding(),
                        );
                      case EHRoutes.galleryComment:
                        return GetPageRoute(
                          page: () => CommentPage(),
                          transition: Transition.rightToLeft,
                        );
                      case EHRoutes.galleryAllPreviews:
                        return GetPageRoute(
                          page: () => const AllPreviewPage(),
                          transition: Transition.rightToLeft,
                        );
                      case EHRoutes.addTag:
                        return GetPageRoute(
                          page: () => AddTagPage(),
                          transition: Transition.rightToLeft,
                          binding: BindingsBuilder(
                            () => Get.lazyPut(() => TagInfoController(),
                                tag: pageCtrlDepth),
                          ),
                        );
                      case EHRoutes.galleryInfo:
                        return GetPageRoute(
                          page: () => const GalleryInfoPage(),
                          transition: Transition.rightToLeft,
                        );
                      case EHRoutes.pageSetting:
                        return GetPageRoute(
                          page: () => TabSettingPage(),
                          binding: BindingsBuilder(
                            () => Get.lazyPut(() => TabSettingController()),
                          ),
                          transition: Transition.rightToLeft,
                        );
                      default:
                        return GetPageRoute(
                          page: () => CupertinoTheme(
                            data: ehTheme.themeData!,
                            child: CupertinoPageScaffold(
                              child: Container(
                                color:
                                    ehTheme.themeData!.scaffoldBackgroundColor,
                                child: const Center(
                                  child: Text(
                                    '[ ]',
                                    style: TextStyle(fontSize: 50),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          transition: Transition.fadeIn,
                        );
                    }
                  },
                ),
              ),
            ],
          ),
          // child: CupertinoPageScaffold(child: Container()),
        ),
      ],
    );
  }
}
