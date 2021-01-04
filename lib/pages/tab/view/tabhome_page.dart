import 'package:fehviewer/pages/tab/controller/tabhome_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class TabHome extends GetView<TabHomeControllerNew> {
  @override
  Widget build(BuildContext context) {
    controller.init(inContext: context);

    final WillPopScope willPopScope = WillPopScope(
      onWillPop: controller.doubleClickBack,
      child: Obx(() => CupertinoTabScaffold(
            controller: controller.tabController,
            tabBar: CupertinoTabBar(
              items: controller.listBottomNavigationBarItem,
              onTap: controller.onTap,
            ),
            tabBuilder: (BuildContext context, int index) {
              // return controller.pageList[index];
              return CupertinoTabView(
                builder: (BuildContext context) {
                  return controller.viewList[index];
                },
              );
            },
          )),
    );

    return willPopScope;
  }
}
