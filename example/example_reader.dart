import 'dart:io';
import 'dart:typed_data';

import 'package:capnp/capnp.dart';
import 'addressbook_capnp.dart';

void main() async {
  final filename = 'serialize_test.bin';
  Uint8List buffer = await File(filename).readAsBytes();
  var msg = CapnpMessage.fromBuffer(buffer.buffer);
  var root = msg.readRoot(AddressBook().reader);
  print(root.people.length);
  print(root.people[0].name);
  print(root.people[0].employment.employer);
  print(root.people[1].phones[2].number);
}
