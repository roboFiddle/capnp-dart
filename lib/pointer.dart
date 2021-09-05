import 'constants.dart';
import 'objects/list.dart';
import 'objects/struct.dart';
import 'segment.dart';

enum PointerType { struct, list, interSegment, capability }
enum InterSegmentPointerType { Simple, LandingPad }

typedef _PointerFactory<P extends Pointer> = P Function(
  SegmentView segmentView,
);

abstract class Pointer {
  Pointer(this.segmentView) : assert(segmentView.lengthInWords == lengthInWords);
  static P resolvedFromSegmentView<P extends Pointer>(
    SegmentView segmentView,
    _PointerFactory<P> factory,
  ) {
    while (typeOf(segmentView) == PointerType.interSegment) {
      segmentView = InterSegmentPointer.fromView(segmentView).target;
    }
    return factory(segmentView);
  }

  static PointerType typeOf(SegmentView segmentView) {
    assert(segmentView.lengthInWords == Pointer.lengthInWords);
    final rawType = segmentView.getUInt8(0) & 0x3;
    switch (rawType) {
      case 0x00:
        return PointerType.struct;
      case 0x01:
        return PointerType.list;
      case 0x02:
        return PointerType.interSegment;
      case 0x03:
        throw StateError('Capability pointers are not yet supported.');
      default:
        throw FormatException("Unsigned 2-bit number can't be outside 0 – 3.");
    }
  }

  static const lengthInWords = 1;

  final SegmentView segmentView;
}

class StructPointer extends Pointer {
  factory StructPointer.inSegment(Segment segment, int offsetInWords) =>
      StructPointer.fromView(segment.view(offsetInWords, 1));
  StructPointer.fromView(SegmentView segmentView)
      : assert(Pointer.typeOf(segmentView) == PointerType.struct),
        super(segmentView);
  factory StructPointer.resolvedFromView(SegmentView segmentView) {
    return Pointer.resolvedFromSegmentView(
      segmentView,
      (it) => StructPointer.fromView(it),
    );
  }

  int get offsetInWords => segmentView.getInt32(0) >> 2;

  int get dataSectionLengthInWords => segmentView.getUInt16(4);
  int get pointerSectionLengthInWords => segmentView.getUInt16(6);

  SegmentView get structView {
    return segmentView.viewRelativeToEnd(
      offsetInWords,
      dataSectionLengthInWords + pointerSectionLengthInWords,
    );
  }

  T load<T>(StructFactory<T> factory) => factory(structView, dataSectionLengthInWords);

  static void save(SegmentView view, int offsetInWordsIntoSegment, int offsetToStructInWords,
      int dataSectionLengthInWords, int pointerSectionLengthInWords) {
    view.setUInt32(offsetInWordsIntoSegment * CapnpConstants.bytesPerWord, offsetToStructInWords << 2);
    view.setUInt32(offsetInWordsIntoSegment * CapnpConstants.bytesPerWord + 4,
        dataSectionLengthInWords | pointerSectionLengthInWords << 16);
  }
}

/// https://capnproto.org/encoding.html#lists
class ListPointer extends Pointer {
  ListPointer.fromView(SegmentView segmentView)
      : assert(Pointer.typeOf(segmentView) == PointerType.list),
        super(segmentView);
  factory ListPointer.resolvedFromView(SegmentView segmentView) {
    return Pointer.resolvedFromSegmentView(
      segmentView,
      (it) => ListPointer.fromView(it),
    );
  }

  int get offsetInWords => segmentView.getInt32(0) >> 2;

  int get _rawElementSize => segmentView.getUInt8(4) & 0x07;
  bool get isCompositeList => _rawElementSize == 7;
  int get elementSizeInBits {
    switch (_rawElementSize) {
      case 0:
        return 0;
      case 1:
        return 1;
      case 2:
        return 1 * CapnpConstants.bitsPerByte;
      case 3:
        return 2 * CapnpConstants.bitsPerByte;
      case 4:
        return 4 * CapnpConstants.bitsPerByte;
      case 5:
      case 6:
        return 8 * CapnpConstants.bitsPerByte;
      case 7:
        // TODO(JonasWanke): Better return value for composite lists?
        return -1;
      default:
        throw StateError("Unsigned 3-bit number can't be outside 0 – 7.");
    }
  }

  int get _rawListSize => segmentView.getUInt32(4) >> 3;
  int get elementCount {
    assert(!isCompositeList);
    return _rawListSize;
  }

  int get wordCount {
    assert(isCompositeList);
    return 1 + _rawListSize;
  }

  SegmentView get targetView {
    assert(!isCompositeList, 'CompositeListPointer overwrites this field.');
    final lengthInWords = (elementSizeInBits * elementCount / CapnpConstants.bitsPerWord).ceil();
    return segmentView.viewRelativeToEnd(offsetInWords, lengthInWords);
  }

  static void save(SegmentView view, int offsetInWordsIntoSegment, int offset, int elementSize, int length) {
    view.setUInt32(offsetInWordsIntoSegment * CapnpConstants.bytesPerWord, 0x01 | offset << 2);
    view.setUInt32(offsetInWordsIntoSegment * CapnpConstants.bytesPerWord + 4, elementSize | length << 3);
  }
}

class CompositeListPointer<T> extends ListPointer {
  CompositeListPointer.fromView(SegmentView segmentView, this.factory) : super.fromView(segmentView) {
    assert(isCompositeList);
  }
  factory CompositeListPointer.resolvedFromView(
    SegmentView segmentView,
    StructFactory<T> factory,
  ) {
    return Pointer.resolvedFromSegmentView(
      segmentView,
      (it) => CompositeListPointer.fromView(it, factory),
    );
  }

  final StructFactory<T> factory;

  @override
  SegmentView get targetView {
    return segmentView.segment.view(segmentView.offsetInWords + offsetInWords + 1, wordCount);
  }

  CompositeList<T> get value => CompositeList.fromPointer(this);
}

/// https://capnproto.org/encoding.html#inter-segment-pointers
class InterSegmentPointer extends Pointer {
  InterSegmentPointer.fromView(SegmentView segmentView)
      : assert(Pointer.typeOf(segmentView) == PointerType.interSegment),
        // TODO(JonasWanke): support other variant
        assert(segmentView.getUInt8(0) & 0x4 == 0x00),
        super(segmentView);

  int get offsetInWords => segmentView.getUInt32(0) >> 3;
  int get targetSegmentId => segmentView.getUInt32(4);

  SegmentView get target {
    // print("got interseg target $targetSegmentId");
    final targetSegment = segmentView.segment.message.segments[targetSegmentId];
    return targetSegment.view(offsetInWords, 1);
  }

  static void save(SegmentView view, int offsetInWordsIntoSegment, InterSegmentPointerType ty,
      int offsetToPointerIntoPointer, int segmentID) {
    int ty_int = ty == InterSegmentPointerType.Simple ? 0 : 1;
    int leading = 0x02 | ty_int << 2 | offsetToPointerIntoPointer << 3;

    view.setUInt32(offsetInWordsIntoSegment * CapnpConstants.bytesPerWord, leading);
    view.setUInt32(offsetInWordsIntoSegment * CapnpConstants.bytesPerWord + 4, segmentID);
  }
}
