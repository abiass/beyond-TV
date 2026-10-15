/// Valores do campo `type` do envelope.
abstract final class MessageTypes {
  // TV → servidor
  static const hello = 'hello';
  static const heartbeat = 'heartbeat';
  static const ack = 'ack';
  static const screenshotResult = 'screenshot.result';
  static const error = 'error';

  // Servidor → TV
  static const contentSync = 'content.sync';
  static const cmdReload = 'cmd.reload';
  static const cmdIdentify = 'cmd.identify';
  static const cmdScreenshot = 'cmd.screenshot';
  static const cmdUnpair = 'cmd.unpair';

  // Servidor → dashboard
  static const deviceOnline = 'device.online';
  static const deviceOffline = 'device.offline';
  static const devicePaired = 'device.paired';
  static const deviceState = 'device.state';
  static const deviceRemoved = 'device.removed';
  static const deviceScreenshot = 'device.screenshot';
}
