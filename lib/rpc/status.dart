enum ErrorTag { Unimplemented, Disconnected, Failed }

class Status {
  ErrorTag? tag;
  String? value;

  Status.ok();
  Status.unimplemented(this.value) : tag = ErrorTag.Unimplemented;
}
