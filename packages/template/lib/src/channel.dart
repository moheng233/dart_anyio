import 'dart:async';
import 'dart:isolate';

import 'template.dart';

typedef ChannelOptionGroup = ({
  String deviceId,
  ChannelOptionBase channel,
  ChannelTemplateBase template,
});

typedef ChannelFactoryHandler =
    Future<void> Function(List<ChannelOptionGroup> devices, SendPort inPort);
