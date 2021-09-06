import 'dart:async';
import 'dart:io';

import 'package:capnp/rpc/connection.dart';
import 'package:capnp/rpc/schemas/rpc_twoparty_capnp.dart';
import 'package:capnp/rpc/status.dart';

import 'pubsub_capnp.dart';
import 'pubsub_subscriber_capnp.dart';

class MySubscriber extends SubscriberServer {
  int count = 0;
  Completer<bool> finish;

  MySubscriber(this.finish);

  @override
  FutureOr<Status> pushMessage(PushMessageParamsReader params, PushMessageResultsBuilder results) {
    print("received message ${params.message}");
    count++;
    if (count == 10) {
      finish.complete(true);
    }
    return Status.ok();
  }
}

void main() async {
  var connection = await Socket.connect('172.29.77.80', 8080);
  print("connection made");
  var rpc = RpcSystem(connection, connection, Side.Client);
  var publisher_client = (await rpc.bootstrap(Publisher().clientBuilder))!;

  var finish = Completer<bool>();
  var subscriber = MySubscriber(finish);
  var subscriber_client = rpc.newClient(subscriber, Subscriber().clientBuilder);

  var subreq = publisher_client.subscribeRequest;
  subreq.params.initSubscriber.initCap(subscriber_client.innerClient);
  var subreq_result = await subreq.send();
  subreq_result.finish();

  await finish.future;

  subreq_result.results.subscription.innerClient.release();
  await Future.delayed(const Duration(milliseconds: 100), () => null);
  exit(0);
}
