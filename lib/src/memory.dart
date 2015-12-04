library minic.src.memory;

import 'dart:math';
import 'dart:typed_data' show ByteData;

/// Return the number of bytes required to represent `n` values.
int calculateRequiredBytes(int n) => (log(n) / log(256)).ceil();

/// Possible ways to interpret buffer.
///
/// Other number encodings are not supported by [ByteData], so we don't support
/// them either.
enum NumberType {
  uint8,
  uint16,
  uint32,
  uint64,
  sint8,
  sint16,
  sint32,
  sint64,
  fp32,
  fp64
}

/// Number of bytes needed to encode a value as [NumberType].
final Map<NumberType, int> numberTypeByteCount = {
  NumberType.uint8: 1,
  NumberType.uint16: 2,
  NumberType.uint32: 4,
  NumberType.uint64: 8,
  NumberType.sint8: 1,
  NumberType.sint16: 2,
  NumberType.sint32: 4,
  NumberType.sint64: 8,
  NumberType.fp32: 4,
  NumberType.fp64: 8
};

/// Bitmasks that mask the bytes of the respective number type.
final Map<NumberType, int> numberTypeBitmasks =
    new Map<NumberType, int>.fromIterable(NumberType.values,
        key: (numberType) => numberType,
        value: (numberType) => pow(2, 8 * numberTypeByteCount[numberType]) - 1);

/// Wrapper class around [ByteData]. Its only purpose is to map a [NumberType]
/// argument to the appropriate named method in ByteData.
class MemoryBlock {
  ByteData buffer;

  /// Create a fixed size memory block.
  MemoryBlock(int size) : buffer = new ByteData(size);

  /// Read [buffer] at address as the specified number type.
  num getValue(int address, NumberType numberType) {
    switch (numberType) {
      case NumberType.uint8:
        return buffer.getUint8(address);
      case NumberType.uint16:
        return buffer.getUint16(address);
      case NumberType.uint32:
        return buffer.getUint32(address);
      case NumberType.uint64:
        return buffer.getUint64(address);
      case NumberType.sint8:
        return buffer.getInt8(address);
      case NumberType.sint16:
        return buffer.getInt16(address);
      case NumberType.sint32:
        return buffer.getInt32(address);
      case NumberType.sint64:
        return buffer.getInt64(address);
      case NumberType.fp32:
        return buffer.getFloat32(address);
      case NumberType.fp64:
        return buffer.getFloat64(address);
    }
  }

  /// Insert value into [buffer] at the specified address, encoded as the
  /// specified number type.
  void setValue(int address, NumberType numberType, num value) {
    if (numberType == NumberType.fp32 || numberType == NumberType.fp64) value =
        value.toDouble();
    else value = value.toInt() & numberTypeBitmasks[numberType];

    switch (numberType) {
      case NumberType.uint8:
        buffer.setUint8(address, value);
        break;
      case NumberType.uint16:
        buffer.setUint16(address, value);
        break;
      case NumberType.uint32:
        buffer.setUint32(address, value);
        break;
      case NumberType.uint64:
        buffer.setUint64(address, value);
        break;
      case NumberType.sint8:
        buffer.setInt8(address, value);
        break;
      case NumberType.sint16:
        buffer.setInt16(address, value);
        break;
      case NumberType.sint32:
        buffer.setInt32(address, value);
        break;
      case NumberType.sint64:
        buffer.setInt64(address, value);
        break;
      case NumberType.fp32:
        buffer.setFloat32(address, value);
        break;
      case NumberType.fp64:
        buffer.setFloat64(address, value);
        break;
    }
  }
}
