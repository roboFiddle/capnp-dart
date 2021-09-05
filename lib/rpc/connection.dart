import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:capnp/rpc/schemas/rpc_twoparty_capnp.dart';
import '../message.dart' as raw;
import 'schemas/rpc_capnp.dart';

class RawClient {}

typedef ClientFactory<T> = T Function(RawClient);

class RpcSystem {
  Stream<Uint8List> read;
  IOSink write;
  Side side;
  late StreamSubscription readSubscribe;

  int currentQuestion = 0;

  Map<int, Completer<PayloadReader>> awaitingQuestions = {};

  void handleReturn(ReturnReader reader) {
    print("Answer ${reader.answerId}");
    switch (reader.which()) {
      case ReturnTag.Results:
        awaitingQuestions[reader.answerId]!.complete(reader.results);
        break;
      case ReturnTag.Exception:
        // TODO: Handle this case.
        awaitingQuestions[reader.answerId]!.completeError(0);
        break;
      case ReturnTag.Canceled:
        // TODO: Handle this case.
        awaitingQuestions[reader.answerId]!.completeError(0);
        break;
      default:
        print("Return tag not yet implemented: ${reader.which()}");
        break;
    }
  }

  void onRead(Uint8List message) {
    var msg = raw.Message.fromBuffer(message.buffer);
    MessageReader reader = msg.readRoot(Message().reader);
    print(reader.which());
    switch (reader.which()) {
      case MessageTag.Return:
        handleReturn(reader.return_!);
        break;
      default:
        print("received unknown message type");
        break;
    }
  }

  RpcSystem(this.read, this.write, this.side) {
    readSubscribe = read.listen(this.onRead);
  }

  int getQuestionId() {
    int reserved = currentQuestion;
    currentQuestion++;
    return reserved;
  }

  Future<RawClient?> bootstrapRaw() async {
    var bootstrapMsg = raw.Message.empty();
    var bootstrapMsgBuilder = bootstrapMsg.initRoot(Message().builder);
    var bootstrapMsgBootstrapBuilder = bootstrapMsgBuilder.initBootstrap();
    bootstrapMsgBootstrapBuilder.questionId = getQuestionId();
    Completer<PayloadReader> result = Completer();
    awaitingQuestions[bootstrapMsgBootstrapBuilder.reader.questionId] = result;
    write.add(bootstrapMsg.serialize());
    await result.future;
    print("received bootstrap");
  }

  Future<T?> bootstrap<T>(ClientFactory<T> factory) async {
    var raw = await bootstrapRaw();
    if (raw != null) {
      return factory(raw);
    }
  }

  void close() async {
    await readSubscribe.cancel();
  }
}
