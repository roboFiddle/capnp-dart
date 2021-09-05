import '../constants.dart';
import '../segment.dart';

class NullableVoid {}

class Layout {
  int dataSectionLengthInWords;
  int numPointers;

  Layout(this.dataSectionLengthInWords, this.numPointers);

  int words() {
    return dataSectionLengthInWords + numPointers;
  }

  int bytes() {
    return words() * CapnpConstants.bytesPerWord;
  }
}

class BuilderReturn<T> {
  Layout layout;
  T Function(SegmentView root) builder;

  BuilderReturn(this.layout, this.builder);
}

typedef StructFactory<T> = T Function(
  SegmentView segmentView,
  int dataSectionLengthInWords,
);

typedef StructBuilderFactory<T> = BuilderReturn<T> Function();
