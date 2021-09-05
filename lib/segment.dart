import 'dart:typed_data';

import 'package:capnp/capnp.dart';

import 'constants.dart';
import 'message.dart';
import 'objects/list.dart';
import 'objects/struct.dart';
import 'pointer.dart';

class Segment {
  Segment(this.message, this.data) : assert(data.lengthInBytes % CapnpConstants.bytesPerWord == 0);

  Message message;
  ByteData data;
  int get lengthInBytes => data.lengthInBytes;

  SegmentView fullView() => SegmentView._(this, 0, lengthInBytes ~/ 8);

  SegmentView view(int offsetInWords, int lengthInWords) => SegmentView._(this, offsetInWords, lengthInWords);
}

class SegmentView {
  SegmentView._(this.segment, this.offsetInWords, this.lengthInWords)
      : assert(offsetInWords >= 0),
        assert(lengthInWords >= 0),
        assert((offsetInWords + lengthInWords) * CapnpConstants.bytesPerWord <= segment.lengthInBytes),
        data = segment.data.buffer.asByteData(
          segment.data.offsetInBytes + offsetInWords * CapnpConstants.bytesPerWord,
          lengthInWords * CapnpConstants.bytesPerWord,
        );

  final Segment segment;
  final ByteData data;
  final int offsetInWords;
  int get offsetInBytes => offsetInWords * CapnpConstants.bytesPerWord;
  int get totalOffsetInBytes => segment.data.offsetInBytes + offsetInBytes;
  final int lengthInWords;
  int get lengthInBytes => lengthInWords * CapnpConstants.bytesPerWord;

  SegmentView subview(int offsetInWords, int lengthInWords) {
    assert(offsetInWords >= 0);
    assert(lengthInWords >= 0);
    assert(offsetInWords + lengthInWords <= this.lengthInWords);

    return SegmentView._(
      segment,
      this.offsetInWords + offsetInWords,
      lengthInWords,
    );
  }

  SegmentView viewRelativeToEnd(int offsetInWords, int lengthInWords) {
    assert(offsetInWords >= 0);
    assert(lengthInWords >= 0);

    return SegmentView._(
      segment,
      this.offsetInWords + offsetInWords + this.lengthInWords,
      lengthInWords,
    );
  }

  // Primitives:
  NullableVoid getVoid(int offsetInBytes) => NullableVoid();

  void setVoid(int offsetInBytes, NullableVoid value) {}

  bool getBool(int offsetInBits, {bool defaultValue = false}) {
    final byte = data.getUint8(offsetInBits ~/ CapnpConstants.bitsPerByte);
    final bitIndex = offsetInBits % CapnpConstants.bitsPerByte;
    final bit = (byte >> bitIndex) & 1;
    return bit == 1;
  }

  void setBool(int offsetInBits, bool value, {bool defaultValue = false}) {
    value ^= defaultValue;
    int valueAsInt = value as int;
    int byteOffset = offsetInBits ~/ CapnpConstants.bitsPerByte;
    int byte = data.getUint8(byteOffset);
    final bitIndex = offsetInBits % CapnpConstants.bitsPerByte;
    byte &= (valueAsInt << bitIndex);
    data.setUint8(byteOffset, byte);
  }

  int getUInt8(int offsetInBytes, {int defaultValue = 0}) => data.getUint8(offsetInBytes) ^ defaultValue;
  int getUInt16(int offsetInBytes, {int defaultValue = 0}) =>
      data.getUint16(offsetInBytes, Endian.little) ^ defaultValue;
  int getUInt32(int offsetInBytes, {int defaultValue = 0}) =>
      data.getUint32(offsetInBytes, Endian.little) ^ defaultValue;
  int getUInt64(int offsetInBytes, {int defaultValue = 0}) =>
      data.getUint64(offsetInBytes, Endian.little) ^ defaultValue;

  int getInt8(int offsetInBytes, {int defaultValue = 0}) => data.getInt8(offsetInBytes) ^ defaultValue;
  int getInt16(int offsetInBytes, {int defaultValue = 0}) => data.getInt16(offsetInBytes, Endian.little) ^ defaultValue;
  int getInt32(int offsetInBytes, {int defaultValue = 0}) => data.getInt32(offsetInBytes, Endian.little) ^ defaultValue;
  int getInt64(int offsetInBytes, {int defaultValue = 0}) => data.getInt64(offsetInBytes, Endian.little) ^ defaultValue;

  double getFloat32(int offsetInBytes, {int? defaultValue}) => data.getFloat32(offsetInBytes, Endian.little);
  double getFloat64(int offsetInBytes, {int? defaultValue}) => data.getFloat64(offsetInBytes, Endian.little);

  void setInt8(int offsetInBytes, int value, {int defaultValue = 0}) =>
      data.setInt8(offsetInBytes, value ^ defaultValue);

  void setInt16(int offsetInBytes, int value, {int defaultValue = 0}) =>
      data.setInt16(offsetInBytes, value ^ defaultValue, Endian.little);

  void setInt32(int offsetInBytes, int value, {int defaultValue = 0}) =>
      data.setInt32(offsetInBytes, value ^ defaultValue, Endian.little);

  void setInt64(int offsetInBytes, int value, {int defaultValue = 0}) =>
      data.setInt64(offsetInBytes, value ^ defaultValue, Endian.little);

  void setUInt8(int offsetInBytes, int value, {int defaultValue = 0}) =>
      data.setUint8(offsetInBytes, value ^ defaultValue);

  void setUInt16(int offsetInBytes, int value, {int defaultValue = 0}) =>
      data.setUint16(offsetInBytes, value ^ defaultValue, Endian.little);

  void setUInt32(int offsetInBytes, int value, {int defaultValue = 0}) =>
      data.setUint32(offsetInBytes, value ^ defaultValue, Endian.little);

  void setUInt64(int offsetInBytes, int value, {int defaultValue = 0}) =>
      data.setUint64(offsetInBytes, value ^ defaultValue, Endian.little);

  void setFloat32(int offsetInBytes, double value, {int defaultValue = 0}) =>
      data.setFloat32(offsetInBytes, value, Endian.little);

  void setFloat64(int offsetInBytes, double value, {int defaultValue = 0}) =>
      data.setFloat64(offsetInBytes, value, Endian.little);

  String getText(int offsetInWords) {
    var view = subview(offsetInWords, 1);
    final pointer = ListPointer.resolvedFromView(view);
    return Text(pointer).value;
  }

  void setText(int offsetIntoView, String text) {
    segment.message.newTextSegment(this, offsetIntoView, text);
  }

  UnmodifiableUint8ListView getData(int offsetInWords) {
    final pointer = ListPointer.resolvedFromView(subview(offsetInWords, 1));
    return CapnpUInt8List(pointer).value;
  }

  // Nested structs:
  T getStruct<T>(int offsetInWords, StructFactory<T> factory) {
    final pointer = StructPointer.resolvedFromView(subview(offsetInWords, 1));
    return factory(pointer.structView, pointer.dataSectionLengthInWords);
  }

  T newStruct<T>(int offsetInWords, StructBuilderFactory<T> factory) {
    return segment.message.newStructSegment(this, offsetInWords, factory);
  }

  void setStruct<T>(int offsetInWords, T reader) {
    throw UnimplementedError;
  }

  // Enums:
  T getEnum<T>(int offsetInBytes, List<T> values) {
    return values[getUInt16(offsetInBytes)];
  }

  // Lists of primitives:
  UnmodifiableBoolListView getBoolList(int offsetInWords) {
    final pointer = ListPointer.resolvedFromView(subview(offsetInWords, 1));
    return CapnpBoolList(pointer).value;
  }

  UnmodifiableUint8ListView getUInt8List(int offsetInWords) {
    final pointer = ListPointer.resolvedFromView(subview(offsetInWords, 1));
    return CapnpUInt8List(pointer).value;
  }

  UnmodifiableUint16ListView getUInt16List(int offsetInWords) {
    final pointer = ListPointer.resolvedFromView(subview(offsetInWords, 1));
    return CapnpUInt16List(pointer).value;
  }

  UnmodifiableUint32ListView getUInt32List(int offsetInWords) {
    final pointer = ListPointer.resolvedFromView(subview(offsetInWords, 1));
    return CapnpUInt32List(pointer).value;
  }

  UnmodifiableUint64ListView getUInt64List(int offsetInWords) {
    final pointer = ListPointer.resolvedFromView(subview(offsetInWords, 1));
    return CapnpUInt64List(pointer).value;
  }

  UnmodifiableInt8ListView getInt8List(int offsetInWords) {
    final pointer = ListPointer.resolvedFromView(subview(offsetInWords, 1));
    return CapnpInt8List(pointer).value;
  }

  UnmodifiableInt16ListView getInt16List(int offsetInWords) {
    final pointer = ListPointer.resolvedFromView(subview(offsetInWords, 1));
    return CapnpInt16List(pointer).value;
  }

  UnmodifiableInt32ListView getInt32List(int offsetInWords) {
    final pointer = ListPointer.resolvedFromView(subview(offsetInWords, 1));
    return CapnpInt32List(pointer).value;
  }

  UnmodifiableInt64ListView getInt64List(int offsetInWords) {
    final pointer = ListPointer.resolvedFromView(subview(offsetInWords, 1));
    return CapnpInt64List(pointer).value;
  }

  UnmodifiableFloat32ListView getFloat32List(int offsetInWords) {
    final pointer = ListPointer.resolvedFromView(subview(offsetInWords, 1));
    return CapnpFloat32List(pointer).value;
  }

  // Complex types:
  UnmodifiableCompositeListView<T> getCompositeList<T>(
    int offsetInWords,
    StructFactory<T> factory,
  ) {
    final pointer = CompositeListPointer.resolvedFromView(
      subview(offsetInWords, 1),
      factory,
    );
    return UnmodifiableCompositeListView(CompositeList.fromPointer(pointer));
  }

  CompositeList<T> newCompositeList<T>(int offsetIntoView, int numElements, StructBuilderFactory<T> factory) {
    var built = factory();
    ByteData data = ByteData(16 + built.layout.bytes() * numElements);
    Segment segment = Segment(this.segment.message, data);
    ListPointer.save(segment.fullView(), 0, 0, 7, built.layout.words() * numElements);
    StructPointer.save(
        segment.fullView(), 1, numElements, built.layout.dataSectionLengthInWords, built.layout.numPointers);

    CompositeListPointer<T> ptr = CompositeListPointer.resolvedFromView(
        segment.view(0, 2 + numElements * built.layout.words()),
        (segmentView, dataSectionLengthInWords) => built.builder(segmentView));

    CompositeList<T> list = CompositeList.fromPointer(ptr);

    int newSegmentId = segment.message.addSegment(segment);
    InterSegmentPointer.save(this, offsetIntoView, InterSegmentPointerType.Simple, 0, newSegmentId);

    return list;
  }

  CapabilityList newCapabilityList(int offsetInWords, int len) {
    throw UnimplementedError;
  }

  CapabilityList getCapabilityList(int offsetInWords) {
    throw UnimplementedError;
  }

  Pointer getAnyPointer(int offsetInWords) {
    throw UnimplementedError;
  }

  void setAnyPointer(int offsetInWords, Pointer P) {
    throw UnimplementedError;
  }
}
