import 'dart:async';
import 'dart:isolate';

import 'package:dart_mappable/dart_mappable.dart';

import 'event.dart';
import 'template.dart';

typedef ChannelOptionGroup = ({
  String deviceId,
  ChannelOptionBase channel,
  ChannelTemplateBase template,
});

typedef ChannelFactoryHandler =
    Future<void> Function(List<ChannelOptionGroup> devices, SendPort inPort);
