import 'schemas/rpc_capnp.dart' as rpc_schema;

enum ErrorTag {
  Failed,
  Overloaded,
  Disconnected,
  Unimplemented,
}

class Status {
  ErrorTag? tag;
  String? value;

  Status.ok();
  Status.unimplemented(this.value) : tag = ErrorTag.Unimplemented;

  rpc_schema.Type? intoType() {
    switch (tag) {
      case ErrorTag.Unimplemented:
        return rpc_schema.Type.Unimplemented;
      case ErrorTag.Disconnected:
        return rpc_schema.Type.Disconnected;
      case ErrorTag.Failed:
        return rpc_schema.Type.Failed;
      case ErrorTag.Overloaded:
        return rpc_schema.Type.Overloaded;
      case null:
        break;
    }
  }
}
