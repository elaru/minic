library minic.src.memory;

import 'dart:math';
import 'dart:typed_data' show ByteData;

/// Return the number of bytes required to represent `n` values.
int calculateRequiredBytes(int n) => (log(n) / log(256)).ceil();

/// Possible ways to interpret buffer.
///
/// Other number encodings are not supported by [ByteData], so we don't support
/// them either.
class NumberType {
  static const String unsigned = 'u';
  static const String signed = 's';

  /// Number of bytes required to store a value of this type.
  final int size;

  /// Always [int] or [double].
  final Type memoryInterpretation;

  /// One of `NumberType.unsigned` or `NumberType.signed` for integers, `null`
  /// for double types.
  final String sign;

  const NumberType(this.size, this.memoryInterpretation, this.sign);

  static const NumberType uint8 = const NumberType(1, int, unsigned);
  static const NumberType uint16 = const NumberType(2, int, unsigned);
  static const NumberType uint32 = const NumberType(4, int, unsigned);
  static const NumberType uint64 = const NumberType(8, int, unsigned);
  static const NumberType sint8 = const NumberType(1, int, signed);
  static const NumberType sint16 = const NumberType(2, int, signed);
  static const NumberType sint32 = const NumberType(4, int, signed);
  static const NumberType sint64 = const NumberType(8, int, signed);
  static const NumberType fp32 = const NumberType(4, double, null);
  static const NumberType fp64 = const NumberType(8, double, null);

  static const List<NumberType> values = const <NumberType>[
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
  ];

  String toString() => '${sign ?? ''}$memoryInterpretation${8 * size}';
}

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
      default:
        throw new ArgumentError.value(numberType, 'numberType');
    }
  }

  /// Insert value into [buffer] at the specified address, encoded as the
  /// specified number type.
  void setValue(int address, NumberType numberType, num value) {
    if (numberType.memoryInterpretation == double)
      value = value.toDouble();
    else
      value = value.toInt();

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
