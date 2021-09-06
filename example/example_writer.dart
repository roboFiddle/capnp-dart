import 'dart:io';

import 'package:capnp/capnp.dart';
import 'addressbook_capnp.dart' as address_book;

void main() async {
  var msg = CapnpMessage.empty();
  address_book.AddressBookBuilder builder = msg.initRoot(address_book.AddressBookBuilder.build);
  var peopleList = builder.initPeople(2);

  var firstPerson = peopleList[0];
  firstPerson.id = 20;
  firstPerson.name = "Alice Parker";
  firstPerson.email = "alice.parker@gmail.com";
  var firstPersonPhones = firstPerson.initPhones(1);
  firstPersonPhones[0].type = address_book.Type.Mobile;
  firstPersonPhones[0].number = "917-375-2373";
  firstPerson.employment.employer = "Amazon Web Services";

  var secondPerson = peopleList[1];
  secondPerson.id = 5;
  secondPerson.name = "Bob the Builder";
  secondPerson.email = "bob@constructioninc.com";
  var secondPersonPhones = secondPerson.initPhones(3);
  secondPersonPhones[0].type = address_book.Type.Home;
  secondPersonPhones[0].number = "908-267-8931";
  secondPersonPhones[1].type = address_book.Type.Mobile;
  secondPersonPhones[1].number = "908-267-8932";
  secondPersonPhones[2].type = address_book.Type.Work;
  secondPersonPhones[2].number = "973-440-8590";
  secondPerson.employment.school = "University of Chicago";

  List<int> serialized = msg.serialize();
  final filename = 'serialize_test2.bin';
  await File(filename).writeAsBytes(serialized);
}
