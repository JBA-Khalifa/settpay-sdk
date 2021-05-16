import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';
import 'package:settpay_sdk/api/types/balanceData.dart';
import 'package:settpay_sdk/api/types/networkStateData.dart';
import 'package:settpay_sdk/plugin/store/balances.dart';
import 'package:settpay_sdk/settpay_sdk.dart';
import 'package:settpay_sdk/api/types/networkParams.dart';
import 'package:settpay_sdk/plugin/homeNavItem.dart';
import 'package:settpay_sdk/service/webViewRunner.dart';
import 'package:settpay_sdk/storage/keyring.dart';
import 'package:settpay_sdk/storage/types/keyPairData.dart';

const String sdk_cache_key = 'polka_wallet_sdk_cache';
const String net_state_cache_key = 'network_state';
const String net_const_cache_key = 'network_const';
const String balance_cache_key = 'balances';

abstract class SettPayPlugin implements SettPayPluginBase {
  /// A plugin has a [WalletSDK] instance for connecting to it's node.
  final WalletSDK sdk = WalletSDK();

  /// Plugin should retrieve [balances] from sdk
  /// for display in Assets page of SettPay App.
  final balances = BalancesStore();

  final recoveryEnabled = false;

  /// Plugin should retrieve [networkState] & [networkConst] while start
  NetworkStateData get networkState {
    try {
      return NetworkStateData.fromJson(Map<String, dynamic>.from(
          _cache.read(_getNetworkCacheKey(net_state_cache_key)) ?? {}));
    } catch (err) {
      print(err);
    }
    return NetworkStateData();
  }

  Map get networkConst =>
      _cache.read(_getNetworkCacheKey(net_const_cache_key)) ?? {};

  GetStorage get _cache => GetStorage(sdk_cache_key);
  String _getNetworkCacheKey(String key) => '${key}_${basic.name}';
  String _getBalanceCacheKey(String pubKey) =>
      '${balance_cache_key}_${basic.name}_$pubKey';

  Future<void> updateNetworkState() async {
    final state = await Future.wait([
      sdk.api.service.setting.queryNetworkConst(),
      sdk.api.service.setting.queryNetworkProps(),
    ]);
    _cache.write(_getNetworkCacheKey(net_const_cache_key), state[0]);
    _cache.write(_getNetworkCacheKey(net_state_cache_key), state[1]);
  }

  void updateBalances(KeyPairData acc, BalanceData data) {
    balances.setBalance(data);

    _cache.write(_getBalanceCacheKey(acc.pubKey), data.toJson());
  }

  void loadBalances(KeyPairData acc) {
    // do not load balance data from cache if we have no decimals data.
    if (networkState.tokenDecimals == null) return;

    updateBalances(
      acc,
      BalanceData.fromJson(Map<String, dynamic>.from(
          _cache.read(_getBalanceCacheKey(acc.pubKey)) ?? {})),
    );
  }

  /// This method will be called while App switched to a plugin.
  /// In this method, the plugin will init [WalletSDK] and start
  /// a webView for running `polkadot-js/api`.
  Future<void> beforeStart(
    Keyring keyring, {
    WebViewRunner webView,
    String jsCode,
  }) async {
    await sdk.init(
      keyring,
      webView: webView,
      jsCode: jsCode ?? (await loadJSCode()),
    );
    await onWillStart(keyring);
  }

  /// This method will be called while App switched to a plugin.
  /// In this method, the plugin will:
  /// 1. connect to nodes.
  /// 2. retrieve network const & state.
  /// 3. subscribe balances & set balancesStore.
  Future<NetworkParams> start(Keyring keyring,
      {List<NetworkParams> nodes}) async {
    final res = await sdk.api.connectNode(keyring, nodes ?? nodeList);
    if (res == null) return null;

    keyring.setSS58(res.ss58);
    await updateNetworkState();

    if (keyring.current.address != null) {
      loadBalances(keyring.current);
      sdk.api.account.subscribeBalance(keyring.current.address,
          (BalanceData data) {
        updateBalances(keyring.current, data);
      });
    }

    onStarted(keyring);

    return res;
  }

  /// This method will be called while App user changes account.
  void changeAccount(KeyPairData account) {
    sdk.api.account.unsubscribeBalance();
    loadBalances(account);
    sdk.api.account.subscribeBalance(account.address, (BalanceData data) {
      updateBalances(account, data);
    });

    onAccountChanged(account);
  }

  /// This method will be called before plugin start
  Future<void> onWillStart(Keyring keyring) async => null;

  /// This method will be called after plugin started
  Future<void> onStarted(Keyring keyring) async => null;

  /// This method will be called while App user changes account.
  /// In this method, the plugin should do:
  /// 1. update balance subscription to update balancesStore.
  /// 2. update other user state of plugin if needed.
  Future<void> onAccountChanged(KeyPairData account) async => null;

  /// we don't really need this method, calling webView.launch
  /// more than once will cause some exception.
  /// We just pass a [webViewParam] instance to the sdk.init function,
  /// so the sdk knows how to deal with the webView.
  Future<void> dispose() async {
    // do nothing
  }
}

abstract class SettPayPluginBase {
  /// A plugin's basic info, including: name, primaryColor and icons.
  final basic = PluginBasicData(name: 'polkadot', primaryColor: Colors.black);

  /// Plugin should define a list of node to connect
  /// for users of SettPay App.
  List<NetworkParams> get nodeList => List<NetworkParams>();

  /// Plugin should provide [tokenIcons]
  /// for display in Assets page of SettPay App.
  final Map<String, Widget> tokenIcons = {};

  /// The [getNavItems] method returns a list of [HomeNavItem] which defines
  /// the [Widget] to be used in home page of settpay App.
  List<HomeNavItem> getNavItems(BuildContext context, Keyring keyring) =>
      List<HomeNavItem>();

  /// App will add plugin's pages with custom [routes].
  Map<String, WidgetBuilder> getRoutes(Keyring keyring) =>
      Map<String, WidgetBuilder>();

  /// App will inject plugin's [jsCode] into webview to connect.
  Future<String> loadJSCode() => null;
}

class PluginBasicData {
  PluginBasicData({
    this.name,
    this.genesisHash,
    this.ss58,
    this.primaryColor,
    this.gradientColor,
    this.backgroundImage,
    this.icon,
    this.iconDisabled,
    this.jsCodeVersion,
    this.isTestNet = true,
  });
  final String name;
  final String genesisHash;
  final int ss58;
  final MaterialColor primaryColor;
  final Color gradientColor;

  /// The image will be displayed in network-select page
  final AssetImage backgroundImage;

  /// The icons will be displayed in network-select page
  /// in SettPay App.
  final Widget icon;
  final Widget iconDisabled;

  /// JavaScript code version of your plugin.
  ///
  /// SettPay App will perform hot-update for the js code
  /// of your plugin with it.
  final int jsCodeVersion;

  /// Your plugin is connected to a para-chain testNet by default.
  final bool isTestNet;
}
