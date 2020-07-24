import 'package:FEhViewer/common/global.dart';
import 'package:FEhViewer/models/user.dart';
import 'package:FEhViewer/utils/dio_util.dart';
import 'package:FEhViewer/values/const.dart';
import 'package:dio/dio.dart';

class EhUserManager {
  static EhUserManager _instance = EhUserManager._();

  factory EhUserManager() => _instance;

  EhUserManager._();

  Future<User> signIn(String username, String passwd) async {
    HttpManager httpManager =
        HttpManager.getInstance("https://forums.e-hentai.org");
    const url = "/index.php?act=Login&CODE=01";
    const referer = "https://forums.e-hentai.org/index.php?act=Login&CODE=00";
    const origin = "https://forums.e-hentai.org";

    FormData formData = new FormData.fromMap({
      "UserName": username,
      "PassWord": passwd,
      "submit": "Log me in",
      "temporary_https": "off",
      "CookieDate": "1",
    });

    Options options = Options(headers: {"Referer": referer, "Origin": origin});

    Response rult =
        await httpManager.postForm(url, data: formData, options: options);

    // todo 登录异常处理

    var setcookie = rult.headers['set-cookie'];

    var cookieMap = _parseSetCookieString(setcookie);

//    Global.logger.v('$setcookie');

    var cookie = {
      "ipb_member_id": cookieMap["ipb_member_id"],
      "ipb_pass_hash": cookieMap["ipb_pass_hash"],
    };

    if (cookie['ipb_member_id'] == null) {
      throw Exception('login Fail');
    }

    var tmpCookie = getCookieStringFromMap(cookie);

    Map moreCookie = await _getHome(tmpCookie);

    moreCookie.forEach((key, value) {
      cookie.putIfAbsent(key, () => value);
    });

    Map moreCookieEx = await _getExIgneous(tmpCookie);

    moreCookieEx.forEach((key, value) {
      cookie.putIfAbsent(key, () => value);
    });

    // Global.logger.v('$cookie');

    var cookieStr = getCookieStringFromMap(cookie);

    var user = User()
      ..cookie = cookieStr
      ..username = username.replaceFirstMapped(
          RegExp('(^.)'), (match) => match[1].toUpperCase());

    return user;
  }

  /// 通过网页登录的处理
  /// 处理cookie
  /// 以及获取用户名
  Future<User> signInByWeb(Map cookieMap) async {
    // key value去空格
    cookieMap = cookieMap.map((key, value) {
      return new MapEntry(key.toString().trim(), value.toString().trim());
    });

    //
    var cookie = {
      "ipb_member_id": cookieMap["ipb_member_id"],
      "ipb_pass_hash": cookieMap["ipb_pass_hash"],
    };

    var tmpCookie = getCookieStringFromMap(cookie);

    Global.logger.v('$cookieMap');

    Map moreCookie = await _getHome(tmpCookie);

    moreCookie.forEach((key, value) {
      cookie.putIfAbsent(key, () => value);
    });

    Map moreCookieEx = await _getExIgneous(tmpCookie);

    moreCookieEx.forEach((key, value) {
      cookie.putIfAbsent(key, () => value);
    });

    Global.logger.v('$cookie');

    var cookieStr = getCookieStringFromMap(cookie);
    Global.logger.v('$cookieStr');

    var username = await _getUserName(cookie['ipb_member_id'], tmpCookie);

    var user = User()
      ..cookie = cookieStr
      ..username = username;

    return user;
  }

  Future<String> _getUserName(String id, String tmpCookie) async {
    HttpManager httpManager =
        HttpManager.getInstance("https://forums.e-hentai.org");
    var url = '/index.php?showuser=$id';

    Options options = Options(headers: {
      "Cookie": tmpCookie,
    });

    var response = await httpManager.get(url, options: options);

    // Global.logger.v('$response');

    var regExp = RegExp(r'Viewing Profile: (\w+)</div');
    var username = regExp.firstMatch('$response').group(1);

    Global.logger.v('username $username');

    return username;
  }

  Future<Map> _getHome(String tmpCookie) async {
    HttpManager httpManager = HttpManager.getInstance("https://e-hentai.org");
    const url = "/home.php";

    Options options = Options(headers: {
      "Cookie": tmpCookie,
    });

    Response rult = await httpManager.getAll(url, options: options);

    var setcookie = rult.headers['set-cookie'];

    var cookieMap = _parseSetCookieString(setcookie);

    Global.logger.v('$setcookie');

    return cookieMap;
  }

  Future<Map> _getExIgneous(String tmpCookie) async {
    HttpManager httpManager = HttpManager.getInstance(EHConst.EX_BASE_URL);
    const url = "/uconfig.php";

    Options options = Options(headers: {
      "Cookie": tmpCookie,
    });

    Response rult = await httpManager.getAll(url, options: options);

    var setcookie = rult.headers['set-cookie'];

    var cookieMap = _parseSetCookieString(setcookie);

    // Global.logger.v('$setcookie');

    return cookieMap;
  }

  /// 处理SetCookie 转为map
  _parseSetCookieString(List setCookieStrings) {
    var cookie = {};
    RegExp regExp = new RegExp(r"^([^;=]+)=([^;]+);");
    setCookieStrings.forEach((setCookieString) {
//      debugPrint(setCookieString);
      var found = regExp.firstMatch(setCookieString);
      cookie[found.group(1)] = found.group(2);
    });

    return cookie;
  }

  static String getCookieStringFromMap(Map cookie) {
    var texts = [];
    cookie.forEach((key, value) {
      texts.add('$key=$value');
    });
    return texts.join("; ");
  }
}
