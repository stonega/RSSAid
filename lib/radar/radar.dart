import 'dart:convert';
import 'dart:io';

import 'package:rssaid/models/radar.dart';
import 'package:flutter/services.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_proxy/system_proxy.dart';

extension HttpClientExtension on HttpClient {
  Future<HttpClient> autoProxy() async {
    Map<String, String> sysProxy = await SystemProxy.getProxySettings();
    var proxy = "DIRECT";
    if (sysProxy != null) {
      proxy = "PROXY ${sysProxy['host']}:${sysProxy['port']}; DIRECT";
      print("find proxy $proxy");
    }
    this.findProxy = (uri) {
      return proxy;
    };
    return this;
  }
}

extension UriExtension on Uri {
  Future<Uri> expanding() async {
    try {
      var httpClient = await new HttpClient().autoProxy();
      httpClient.connectionTimeout = Duration(seconds: 5);
      var request = await httpClient.headUrl(this);
      request.followRedirects = false;
      var response = await request.close();
      var location = response.headers.value("Location");
      return location != null ? Uri.parse(location) : this;
    } catch (e) {
      return this;
    }
  }
}

class RssHubJsContext {
  JavascriptRuntime flutterJs;

  RssHubJsContext() {
    flutterJs = getJavascriptRuntime();
    flutterJs.onMessage("console", (args) {
      print(args);
    });
  }
  evaluateScript(String filePath) async {
    try {
      var js = await rootBundle.loadString(filePath);
      flutterJs.evaluate(js + " ");
    } catch (error) {
      throw Exception("load js file failed:$error");
    }
  }
}

class RssHub {
  static RssHubJsContext jsContext = new RssHubJsContext();
  static Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  static Future<String> getContentByUrl(Uri uri) async {
    var content = "";
    try {
      var httpClient = await new HttpClient().autoProxy();
      httpClient.connectionTimeout = Duration(seconds: 10);
      var request = await httpClient.getUrl(uri);
      request.headers.set("User-Agent", "RSSAid");
      var response = await request.close();
      if (response.statusCode == HttpStatus.ok) {
        content = await response.transform(utf8.decoder).join();
      }
    } catch (error) {
      print('get content by url failed:$error');
    }
    return content;
  }

  static Future<void> fetchRules() async {
    final SharedPreferences prefs = await _prefs;
    var url =
        'https://cdn.jsdelivr.net/gh/lt94/RSSAid@main/assets/js/radar-rules.js';
    var jsCode = await getContentByUrl(Uri.parse(url));
    if (jsCode.isNotEmpty) {
      prefs.setString("Rules", "$jsCode");
      jsContext.flutterJs.evaluate("$jsCode ");
    } else {
      if (!prefs.containsKey("Rules")) {
        var js = await rootBundle.loadString("assets/js/radar-rules.js");
        prefs.setString("Rules", js);
        await jsContext.evaluateScript('assets/js/radar-rules.js');
      } else {
        jsContext.flutterJs.evaluate(prefs.getString("Rules"));
      }
    }
  }

  static Future<List<Radar>> detecting(String url) async {
    // await fetchRules();
    await jsContext.evaluateScript('assets/js/radar-rules.js');
    await jsContext.evaluateScript('assets/js/url.min.js');
    await jsContext.evaluateScript('assets/js/psl.min.js');
    await jsContext.evaluateScript('assets/js/route-recognizer.min.js');
    await jsContext.evaluateScript('assets/js/route-recognizer.js');
    await jsContext.evaluateScript('assets/js/dom-parser.min.js');
    await jsContext.evaluateScript('assets/js/utils.js');
    await jsContext.evaluateScript('assets/js/url.js');


    Uri uri = await Uri.parse(url).expanding();
    String html = await getContentByUrl(uri);
    try {
      String expression = """
      getPageRSSHub({
                            url: "$url",
                            host: "${uri.host}",
                            path: "${uri.path}",
                            html: `$html`,
                            rules: rules
                        })
      """;
      jsContext.flutterJs.enableHandlePromises();
      var jsResult = jsContext.flutterJs.evaluate(expression);
      var result = jsResult.stringResult;
      return Radar.listFromJson(json.decode(result));
    } on PlatformException catch (e) {
      print('ERRO: ${e.details}');
    }
    return null;
  }
}
