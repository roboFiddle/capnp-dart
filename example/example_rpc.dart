import 'dart:io';

import 'package:capnp/rpc/connection.dart';
import 'package:capnp/rpc/schemas/rpc_twoparty_capnp.dart';

import 'pubsub_capnp.dart';

void main() async {
  var connection = await Socket.connect('172.29.65.161', 8080);
  print("connection made");
  var rpc = RpcSystem(connection, connection, Side.Client);
  print(await rpc.bootstrap(Publisher().clientBuilder) == null);
  exit(0);
}
