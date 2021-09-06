import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:capnp/capnp.dart';
import 'package:capnp/objects/list.dart';
import 'package:capnp/pointer.dart';
import 'package:capnp/rpc/schemas/rpc_twoparty_capnp.dart';
import 'package:capnp/rpc/status.dart';
import 'schemas/rpc_capnp.dart';

class ServerDispatch {
  FutureOr<Status> dispatch(int interfaceId, int methodId, StructPointer params, PayloadBuilder results) {
    return Status.unimplemented("Method not implemented.");
  }
}

class RawClient {
  RpcSystem network;
  bool isLocal;
  int indexOrID;
  int refCount = 1;

  RawClient(this.network, this.isLocal, this.indexOrID);

  void release() {
    assert(refCount > 0);

    if (isLocal) {
      if (--refCount == 0) network.exports.remove(indexOrID);
    } else {
      var msg = CapnpMessage.empty();
      var builder = msg.initRoot(Message().builder).initRelease();
      builder.id = indexOrID;
      builder.referenceCount = 1;

      var serialized = msg.serialize();
      network.write.add(serialized);
    }
  }
}

class Request<ParamsB, ResultsR> {
  RawClient inner;
  int interfaceId;
  int methodId;
  StructBuilderFactory<ParamsB> writeParams;
  StructFactory<ResultsR> readResults;
  CapnpMessage callMsg;
  int questionID;
  late PayloadBuilder payload;
  late ParamsB params;

  Request.fromRaw(this.inner, this.interfaceId, this.methodId, this.writeParams, this.readResults)
      : assert(inner.refCount > 0),
        callMsg = CapnpMessage.empty(),
        questionID = inner.network.getQuestionId() {
    var msgBuilder = callMsg.initRoot(Message().builder);
    var callBuilder = msgBuilder.initCall();
    callBuilder.questionId = questionID;
    callBuilder.interfaceId = interfaceId;
    callBuilder.methodId = methodId;
    callBuilder.sendResultsTo.caller = NullableVoid();
    payload = callBuilder.initParams();
    params = payload.initContent.initStruct(writeParams);
  }

  Future<Response<ResultsR>> send() async {
    var capTable = payload.initCapTable(callMsg.exportedCaps.length);
    for (int i = 0; i < callMsg.exportedCaps.length; i++) {
      if (callMsg.exportedCaps[i].isLocal) {
        capTable[i].senderHosted = callMsg.exportedCaps[i].indexOrID;
      } else {
        capTable[i].receiverHosted = callMsg.exportedCaps[i].indexOrID;
      }
    }

    Completer<PayloadReader> waiter = Completer();
    inner.network.awaitingQuestions[questionID] = waiter;
    var serialized = callMsg.serialize();

    inner.network.write.add(serialized);

    return Response(inner, await waiter.future, readResults, questionID);
  }
}

class Response<ResultsR> {
  RawClient inner;
  PayloadReader responseReader;
  StructFactory<ResultsR> factory;
  int questionID;

  Response(this.inner, this.responseReader, this.factory, this.questionID);

  ResultsR get results => (responseReader.content as StructPointer).load(factory);

  void finish() {
    var msg = CapnpMessage.empty();
    var builder = msg.initRoot(Message().builder).initFinish();
    builder.questionId = questionID;

    // TODO: Fix Codegen Defaults so that this can be false
    builder.releaseResultCaps = true; // default is true, but not in codegen :(

    var serialized = msg.serialize();
    inner.network.write.add(serialized);
  }
}

typedef ClientFactory<T> = T Function(RawClient);

class ExportedServer {
  int refCount = 1;
  ServerDispatch? server;

  ExportedServer(this.server);
}

class RpcSystem {
  Stream<Uint8List> read;
  IOSink write;
  Side side;
  late StreamSubscription readSubscribe;

  int currentQuestion = 0;
  int currentExport = 0;

  Map<int, RawClient> imports = {};
  Map<int, ExportedServer> exports = {};

  Map<int, Completer<PayloadReader>> awaitingQuestions = {};
  Map<int, PayloadReader?> responses = {};

  Side otherSide() {
    switch (side) {
      case Side.Server:
        return Side.Client;
      case Side.Client:
        return Side.Server;
    }
  }

  int getQuestionId() {
    return currentQuestion++;
  }

  int getExportId() {
    return currentExport++;
  }

  RpcSystem(this.read, this.write, this.side) {
    readSubscribe = CapnpMessage.streamListener(read, this.onRead);
  }

  void handleReturn(ReturnReader reader) {
    switch (reader.which()) {
      case ReturnTag.Results:
        for (CapDescriptorReader cap in reader.results!.capTable) {
          switch (cap.which()) {
            case CapDescriptorTag.SenderHosted:
              if (imports.containsKey(cap.senderHosted)) {
                // already have this import
                imports[cap.senderHosted]!.refCount++;
              } else {
                // new import
                imports[cap.senderHosted!] = RawClient(this, false, cap.senderHosted!);
              }
              break;
            case CapDescriptorTag.ReceiverHosted:
              exports[cap.receiverHosted]!.refCount++;
              break;
            default:
              print("Unsupported Capability Type");
              break;
          }
        }
        reader.segmentView.segment.message.capTable = reader.results!.capTable;
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

  void handleCall(CallReader reader) async {
    assert(reader.sendResultsTo.which() == SendResultsToTag.Caller);
    var target = exports[reader.target.importedCap];

    var response = CapnpMessage.empty();
    var responseBuilder = response.initRoot(Message().builder);
    var returnBuilder = responseBuilder.initReturn();
    returnBuilder.answerId = reader.questionId;
    var payloadBuilder = returnBuilder.initResults();
    var result = await target!.server!
        .dispatch(reader.interfaceId, reader.methodId, reader.params.content as StructPointer, payloadBuilder);

    responses[reader.questionId] = payloadBuilder.reader;

    if (result.tag == null) {
      var capTable = payloadBuilder.initCapTable(response.exportedCaps.length);
      for (int i = 0; i < response.exportedCaps.length; i++) {
        if (response.exportedCaps[i].isLocal) {
          exports[response.exportedCaps[i].indexOrID]!.refCount++;
          capTable[i].senderHosted = response.exportedCaps[i].indexOrID;
        } else {
          capTable[i].receiverHosted = response.exportedCaps[i].indexOrID;
        }
      }
    } else {
      var exceptBuilder = returnBuilder.initException();
      exceptBuilder.type = result.intoType()!;
      exceptBuilder.reason = result.value!;
    }

    write.add(response.serialize());
  }

  void handleFinish(FinishReader finish) {
    responses[finish.questionId] = null;
  }

  void handleRelease(ReleaseReader reader) {
    exports[reader.id]!.refCount -= reader.referenceCount;
    if (exports[reader.id]!.refCount == 0) {
      exports[reader.id]!.server = null;
    } else if (exports[reader.id]!.refCount < 0) {
      print("tried to decrement ref count below zero");
    }
  }

  void onRead(CapnpMessage msg) {
    msg.network = this;
    MessageReader reader = msg.readRoot(Message().reader);
    // print(reader.which());
    switch (reader.which()) {
      case MessageTag.Return:
        handleReturn(reader.return_!);
        break;
      case MessageTag.Call:
        handleCall(reader.call!);
        break;
      case MessageTag.Finish:
        handleFinish(reader.finish!);
        break;
      case MessageTag.Release:
        handleRelease(reader.release!);
        break;
      default:
        print("received unknown message type ${reader.which()}");
        break;
    }
  }

  RawClient? resolveCapability(CapabilityPointer ptr, UnmodifiableCompositeListView<CapDescriptorReader> capTable) {
    switch (capTable[ptr.indexInTable].which()) {
      case CapDescriptorTag.None:
        break;
      case CapDescriptorTag.SenderHosted:
        imports[capTable[ptr.indexInTable].senderHosted!] =
            RawClient(this, false, capTable[ptr.indexInTable].senderHosted!);
        return imports[capTable[ptr.indexInTable].senderHosted!];
      case CapDescriptorTag.SenderPromise:
        // TODO: Handle this case.
        break;
      case CapDescriptorTag.ReceiverHosted:
        return RawClient(this, true, capTable[ptr.indexInTable].receiverHosted!);
      case CapDescriptorTag.ReceiverAnswer:
        // TODO: Handle this case.
        break;
      case CapDescriptorTag.ThirdPartyHosted:
        // TODO: Handle this case.
        break;
      default:
        break;
    }
  }

  Future<RawClient?> bootstrapRaw() async {
    var bootstrapMsg = CapnpMessage.empty();
    var bootstrapMsgBuilder = bootstrapMsg.initRoot(Message().builder);
    var bootstrapMsgBootstrapBuilder = bootstrapMsgBuilder.initBootstrap();
    bootstrapMsgBootstrapBuilder.questionId = getQuestionId();
    Completer<PayloadReader> result = Completer();
    awaitingQuestions[bootstrapMsgBootstrapBuilder.reader.questionId] = result;
    write.add(bootstrapMsg.serialize());
    var resultPayload = await result.future;
    print(resultPayload.content.runtimeType);
    if (resultPayload.content is CapabilityPointer) {
      CapabilityPointer capPtr = resultPayload.content as CapabilityPointer;
      return resolveCapability(capPtr, resultPayload.capTable);
    }
  }

  Future<T?> bootstrap<T>(ClientFactory<T> factory) async {
    var raw = await bootstrapRaw();
    if (raw != null) {
      return factory(raw);
    }
  }

  RawClient newRawClient(ServerDispatch dispatch) {
    var exportID = getExportId();
    exports[exportID] = ExportedServer(dispatch);
    return RawClient(this, true, exportID);
  }

  T newClient<T>(ServerDispatch dispatch, ClientFactory<T> factory) {
    var exportID = getExportId();
    exports[exportID] = ExportedServer(dispatch);
    return factory(RawClient(this, true, exportID));
  }

  void close() async {
    await readSubscribe.cancel();
  }
}
