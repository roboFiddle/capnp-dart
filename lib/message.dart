import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart';

import 'constants.dart';
import 'objects/list.dart';
import 'objects/struct.dart';
import 'pointer.dart';
import 'segment.dart';

class Message {
  factory Message.fromBuffer(ByteBuffer buffer) {
    // https://capnproto.org/encoding.html#serialization-over-a-stream
    final data = buffer.asByteData();
    final segmentCount = 1 + data.getUint32(0, Endian.little);

    final message = Message._();
    var offsetInWords = ((1 + segmentCount) / 2).ceil();
    for (var i = 0; i < segmentCount; i++) {
      final segmentLengthInWords = data.getUint32(4 + i * 4, Endian.little);
      final segmentData = buffer.asByteData(
        offsetInWords * CapnpConstants.bytesPerWord,
        segmentLengthInWords * CapnpConstants.bytesPerWord,
      );
      message._addSegment(Segment(message, segmentData));

      offsetInWords += segmentLengthInWords;
    }
    return message;
  }

  factory Message.empty() {
    return Message._();
  }

  // ignore: prefer_collection_literals, Literals create an unmodifiable list.
  Message._() : _segments = <Segment>[];

  final List<Segment> _segments;
  List<Segment> get segments => UnmodifiableListView(_segments);

  void _addSegment(Segment segment) {
    assert(segment.message == this);

    _segments.add(segment);
  }

  int addSegment(Segment segment) {
    _addSegment(segment);
    return segments.length - 1;
  }

  T initRoot<T>(StructBuilderFactory<T> factory) {
    assert(_segments.isEmpty);

    BuilderReturn<T> result = factory();
    int firstSegmentLength = 8 + result.layout.bytes();

    // setup initial segment
    _segments.add(Segment(this, ByteData(firstSegmentLength)));
    StructPointer.save(
        segments.first.fullView(), 0, 0, result.layout.dataSectionLengthInWords, result.layout.numPointers);

    return result.builder(segments.first.view(1, result.layout.words()));
  }

  T readRoot<T>(StructFactory<T> factory) {
    assert(segments.isNotEmpty);

    final pointer = StructPointer.inSegment(segments.first, 0);
    return pointer.load(factory);
  }

  void newTextSegment(SegmentView view, int offsetIntoView, String text) {
    List<int> encoded = utf8.encode(text);
    int numBytes = (8 + encoded.length + 1);
    int paddedBytes = (numBytes / 8).ceil() * 8;
    ByteData data = ByteData(paddedBytes);

    for (int i = 0; i < encoded.length; i++) {
      data.setUint8(8 + i, encoded[i]);
    }

    Segment segment = Segment(this, data);
    ListPointer.save(segment.fullView(), 0, 0, 2, encoded.length + 1);
    _addSegment(segment);
    InterSegmentPointer.save(view, offsetIntoView, InterSegmentPointerType.Simple, 0, _segments.length - 1);
  }

  T newStructSegment<T>(SegmentView view, int offsetIntoView, StructBuilderFactory<T> factory) {
    var built = factory();
    Segment seg = Segment(this, ByteData(8 + built.layout.bytes()));
    StructPointer.save(seg.fullView(), 0, 0, built.layout.dataSectionLengthInWords, built.layout.numPointers);
    int segmentID = addSegment(seg);
    InterSegmentPointer.save(view, offsetIntoView, InterSegmentPointerType.Simple, 0, segmentID);
    return built.builder(seg.fullView());
  }

  CompositeList<T> newCompositeListSegment<T>(
      SegmentView view, int offsetIntoView, int numElements, StructBuilderFactory<T> factory) {
    var built = factory();
    ByteData data = ByteData(16 + built.layout.bytes() * numElements);
    Segment segment = Segment(this, data);
    ListPointer.save(segment.fullView(), 0, 0, 7, built.layout.words() * numElements);
    StructPointer.save(
        segment.fullView(), 1, numElements, built.layout.dataSectionLengthInWords, built.layout.numPointers);

    CompositeListPointer<T> ptr = CompositeListPointer.resolvedFromView(
        segment.view(0, 2 + numElements * built.layout.words()),
        (segmentView, dataSectionLengthInWords) => built.builder(segmentView));

    CompositeList<T> list = CompositeList.fromPointer(ptr);

    _segments.add(segment);
    InterSegmentPointer.save(view, offsetIntoView, InterSegmentPointerType.Simple, 0, _segments.length - 1);

    return list;
  }

  void printDebug() {
    print("Number of Segments: ${segments.length}");
    for (int i = 0; i < segments.length; i++) {
      print("");
      print("Segment $i (length ${segments[i].lengthInBytes})");
      print("-------------------------");
      for (int w = 0; w < segments[i].lengthInBytes ~/ 8; w++) {
        print(hex.encoder.convert(segments[i].data.buffer.asUint8List(w * 8, 8)));
      }
      print("");
    }
  }

  Uint8List serialize() {
    BytesBuilder builder = BytesBuilder();
    builder.add(Uint8List(4)..buffer.asUint32List()[0] = segments.length - 1); // number of segments
    for (Segment seg in segments) {
      builder.add(Uint8List(4)..buffer.asUint32List()[0] = seg.lengthInBytes ~/ 8); // number of segments
    }
    if (segments.length % 2 == 0) {
      builder.add(Uint8List(4));
    }

    for (Segment seg in segments) {
      builder.add(seg.data.buffer.asUint8List());
    }

    return builder.toBytes();
  }
}
