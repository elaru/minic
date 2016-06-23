import 'dart:math';
import 'package:test/test.dart';
import 'package:minic/abstract_machine/code_generator.dart' show instructionSet;
import 'package:minic/abstract_machine/vm.dart';
import 'package:minic/memory.dart';

const isSegfaultSignal = const isInstanceOf<SegfaultSignal>();
final throwsSegfaultSignal = throwsA(isSegfaultSignal);

VM vm;
MemoryBlock program;
int _firstUnusedByteInProgram;

void encodeInstruction(Instruction instruction, [int address]) =>
    program.setValue(address ?? _firstUnusedByteInProgram++, NumberType.uint8,
        instructionSet.lookup(instruction).opcode);

void encodeImmediateArgument(NumberType size, num value) {
  program.setValue(_firstUnusedByteInProgram, size, value);
  _firstUnusedByteInProgram += size.sizeInBytes;
}

void main() {
  setUp(() {
    program = new MemoryBlock(256);
    vm = new VM(program, 256);
    _firstUnusedByteInProgram = 0;
  });

  group('VM', () {
    test('stack grows towards 0', () {
      var sp = vm.stackPointer;
      vm.pushStack(NumberType.uint8, 42);
      expect(vm.stackPointer, equals(sp - 1));
    });

    test('writing to out-of-bounds memory a address causes a segfault', () {
      expect(() => vm.setMemoryValue(999, NumberType.uint8, 1),
          throwsSegfaultSignal);
      expect(() => vm.setMemoryValue(-1, NumberType.uint8, 1),
          throwsSegfaultSignal);
    });

    test('reading from out-of-bounds memory a address causes a segfault', () {
      expect(() => vm.readMemoryValue(999, NumberType.uint8),
          throwsSegfaultSignal);
      expect(
          () => vm.readMemoryValue(-1, NumberType.uint8), throwsSegfaultSignal);
    });

    test('executing instruction not in memory causes a segfault', () {
      vm.programCounter = 999;
      expect(vm.executeNextInstruction, throwsSegfaultSignal);

      vm.programCounter = -1;
      expect(vm.executeNextInstruction, throwsSegfaultSignal);
    });

    test('executing undefined opcode causes a segfault', () {
      program.setValue(0, NumberType.uint8, 255);
      expect(vm.executeNextInstruction, throwsSegfaultSignal);
    });

    test(
        '.executeNextInstruction() increases programCounter '
        'and respects immediate arguments', () {
      encodeInstruction(new PushInstruction(NumberType.uint8));
      encodeImmediateArgument(NumberType.uint8, 1);
      encodeInstruction(new PushInstruction(NumberType.uint16));
      encodeImmediateArgument(NumberType.uint16, 1);
      encodeInstruction(new AddInstruction(NumberType.uint8));

      vm.executeNextInstruction();
      expect(vm.programCounter, equals(2));
      vm.executeNextInstruction();
      expect(vm.programCounter, equals(5));
      vm.executeNextInstruction();
      expect(vm.programCounter, equals(6));
    });
  });

  group('instruction set:', () {
    group('push', () {
      test('places immediate argument on the stack', () {
        var values = {
          NumberType.uint8: 11,
          NumberType.sint16: -123,
          NumberType.fp32: 4.25,
          NumberType.fp64: 3.141e-20,
          NumberType.sint64: -pow(2, 63)
        };
        values.forEach((numberType, value) {
          encodeInstruction(new PushInstruction(numberType));
          encodeImmediateArgument(numberType, value);

          vm.executeNextInstruction();
          expect(vm.popStack(numberType), equals(value));
        });
      });
    });

    group('pop', () {
      test('reduces stack size by immediate argument value', () {
        encodeInstruction(new PopInstruction());
        encodeImmediateArgument(NumberType.uint16, 20);
        vm.stackPointer = 32;

        vm.executeNextInstruction();
        expect(vm.stackPointer, equals(52));
      });
    });

    group('alloc', () {
      test('increases stack size by immediate argument value', () {
        encodeInstruction(new StackAllocateInstruction());
        encodeImmediateArgument(NumberType.uint16, 20);
        vm.stackPointer = 32;

        vm.executeNextInstruction();
        expect(vm.stackPointer, equals(12));
      });
    });

    group('loada', () {
      for (var numberOfBytes in new Iterable.generate(20, (x) => x + 1)) {
        test('fetches memory chunks of $numberOfBytes bytes', () {
          var random = new Random(numberOfBytes);
          var dataAddress = random.nextInt(200);
          var data =
              new List.generate(numberOfBytes, (x) => random.nextInt(255));

          // create test data
          for (int i = 0; i < data.length; i++) {
            vm.setMemoryValue(dataAddress + i, NumberType.uint8, data[i]);
          }

          // execute instruction
          vm.pushStack(addressSize, dataAddress);
          encodeInstruction(new FetchInstruction());
          encodeImmediateArgument(addressSize, numberOfBytes);
          vm.executeNextInstruction();

          // validate copied data
          for (int i in data) {
            expect(vm.popStack(NumberType.uint8), equals(i));
          }
        });
      }
    });

    group('store', () {
      for (var numberOfBytes in new Iterable.generate(20, (x) => x + 1)) {
        test('moves memory chunks of $numberOfBytes bytes', () {
          var random = new Random(numberOfBytes);
          var dataAddress = random.nextInt(200);
          var data =
              new List.generate(numberOfBytes, (x) => random.nextInt(255));

          // create test data
          for (int i in data.reversed) {
            vm.pushStack(NumberType.uint8, i);
          }

          // execute instruction
          vm.pushStack(addressSize, dataAddress);
          encodeInstruction(new StoreInstruction());
          encodeImmediateArgument(addressSize, numberOfBytes);
          vm.executeNextInstruction();

          // validate copied data
          for (int i = 0; i < data.length; i++) {
            expect(vm.readMemoryValue(dataAddress + i, NumberType.uint8),
                equals(data[i]));
          }
        });
      }
    });

    group('loadr', () {
      test('offsets immediate argument by current frame pointer', () {
        vm.framePointer = vm.stackPointer = 100;
        encodeInstruction(new LoadRelativeAddressInstruction());
        encodeImmediateArgument(addressSize, 20);
        vm.executeNextInstruction();
        expect(vm.popStack(addressSize), equals(80));
      });

      test('can target addresses outside of the current frame', () {
        vm.framePointer = vm.stackPointer = 100;
        encodeInstruction(new LoadRelativeAddressInstruction());
        encodeImmediateArgument(addressSize, -10);
        vm.executeNextInstruction();
        expect(vm.popStack(addressSize), equals(110));
      });
    });

    group('halt', () {
      test('throws HaltSignal with exit code from stack', () {
        vm.pushStack(NumberType.uint32, 156);
        encodeInstruction(new HaltInstruction());
        expect(
            vm.executeNextInstruction,
            throwsA(predicate(
                (signal) => signal is HaltSignal && signal.statusCode == 156)));
      });
    });

    group('jump', () {
      test('sets VM.programCounter to immediate value', () {
        encodeInstruction(new JumpInstruction());
        encodeImmediateArgument(addressSize, 33);
        vm.executeNextInstruction();
        expect(vm.programCounter, equals(33));
      });
    });

    group('jumpz', () {
      test('jumps to immediate value if top stack byte is 0', () {
        vm.pushStack(NumberType.uint8, 0);
        encodeInstruction(new JumpZeroInstruction());
        encodeImmediateArgument(addressSize, 9);
        vm.executeNextInstruction();
        expect(vm.programCounter, equals(9));
      });

      test('advances as normal if top stack byte is not 0', () {
        vm.pushStack(NumberType.uint8, 22);
        encodeInstruction(new JumpZeroInstruction());
        encodeImmediateArgument(addressSize, 78);
        vm.executeNextInstruction();
        expect(vm.programCounter, equals(3));
      });
    });

    group('call / return', () {
      test('call backs up and overrides SP, FP and PC', () {
        vm.programCounter = 78;
        vm.stackPointer = 155;
        vm.framePointer = 150;
        vm.extremePointer = 140;
        var expectedNewStackPointer =
            vm.stackPointer - 4 * addressSize.sizeInBytes;

        encodeInstruction(new CallInstruction(), 78);
        vm.pushStack(addressSize, 199);
        vm.executeNextInstruction();

        expect(vm.stackPointer, equals(expectedNewStackPointer));
        expect(vm.framePointer, equals(expectedNewStackPointer));
        expect(vm.programCounter, equals(199));

        expect(vm.popStack(addressSize), equals(78 + 3));
        expect(vm.popStack(addressSize), equals(155));
        expect(vm.popStack(addressSize), equals(150));
        expect(vm.popStack(addressSize), equals(140));
      });

      test('return restores SP, FP, EP, PC', () {
        vm.stackPointer = 220;
        vm.framePointer = 230;
        vm.extremePointer = 210;
        vm.programCounter = 10;
        encodeInstruction(new CallInstruction(), 10);
        encodeInstruction(new ReturnInstruction(), 50);
        vm.pushStack(addressSize, 50);

        vm.executeNextInstruction();
        vm.executeNextInstruction();

        expect(vm.stackPointer, equals(220));
        expect(vm.framePointer, equals(230));
        expect(vm.extremePointer, equals(210));
        expect(vm.programCounter, equals(13));
      });
    });

    group('enter', () {
      test('sets extreme pointer to immediate argument', () {
        vm.framePointer = 53;
        encodeInstruction(new EnterFunctionInstruction());
        encodeImmediateArgument(addressSize, 23);
        vm.executeNextInstruction();
        expect(vm.extremePointer, equals(30));
      });
    });

    group('cast', () {
      var testConversion =
          (NumberType from, NumberType to, num original, [num result]) {
        result ??= original;
        vm.pushStack(from, original);
        encodeInstruction(new TypeConversionInstruction(from, to));
        vm.executeNextInstruction();
        expect(vm.popStack(to), equals(result));
      };

      test('converts between signed widths', () {
        testConversion(NumberType.sint8, NumberType.sint16, -128);
        testConversion(NumberType.sint16, NumberType.sint32, 444);
        testConversion(NumberType.sint32, NumberType.sint64, -8);
      });

      test('converts between signed and float', () {
        testConversion(NumberType.sint32, NumberType.fp32, -120, -120.0);
        testConversion(NumberType.fp32, NumberType.sint32, 52.4, 52);
        testConversion(NumberType.sint64, NumberType.fp64, -1, -1.0);
        testConversion(NumberType.fp64, NumberType.sint64, -1e10, -pow(10, 10));
      });

      test('converts between unsigned and float', () {
        testConversion(NumberType.uint32, NumberType.fp32, 1234, 1234.0);
        testConversion(NumberType.fp32, NumberType.uint32, 0.9, 0);
        testConversion(NumberType.uint64, NumberType.fp64, 2 << 50, 2 << 50);
        testConversion(NumberType.fp64, NumberType.uint64, PI, 3);
      });

      test('converts between float and double', () {
        testConversion(NumberType.fp32, NumberType.fp64, 64.0, 64.0);
        testConversion(NumberType.fp64, NumberType.fp32, 0.5, 0.5);
      });
    });

    group('arithmetic:', () {
      var testArithmetic = (ArithmeticOperationInstruction instruction, num op1,
          num op2, num result) {
        vm.pushStack(instruction.valueType, op1);
        vm.pushStack(instruction.valueType, op2);
        encodeInstruction(instruction);
        vm.executeNextInstruction();
        expect(vm.popStack(instruction.valueType), equals(result));
      };

      group('add', () {
        var testAdd = (NumberType numberType, num op1, num op2, num result) =>
            testArithmetic(new AddInstruction(numberType), op1, op2, result);

        group('<uint>', () {
          test('adds values', () {
            testAdd(NumberType.uint8, 11, 12, 23);
            testAdd(NumberType.uint16, 500, 1, 501);
            testAdd(NumberType.uint32, 100000, 100002, 200002);
            testAdd(NumberType.uint64, 1 << 33, 1 << 34, 3 << 33);
          });

          test('overflows', () {
            for (var numberType in const [
              NumberType.uint8,
              NumberType.uint16,
              NumberType.uint32,
              NumberType.uint64
            ]) {
              testAdd(numberType, numberType.bitmask, 2, 1);
            }
          });
        });

        group('<sint>', () {
          test('adds values', () {
            testAdd(NumberType.sint8, 50, -3, 47);
            testAdd(NumberType.sint16, -300, 5, -295);
            testAdd(NumberType.sint32, pow(2, 28), 1, pow(2, 28) + 1);
            testAdd(NumberType.sint64, -pow(2, 40), -pow(2, 9),
                -pow(2, 40) + -pow(2, 9));
          });

          test('overflows', () {
            testAdd(NumberType.sint8, 127, 1, -128);
            testAdd(NumberType.sint16, -pow(2, 15), -1, pow(2, 15) - 1);
          });
        });

        test('<float> adds values', () {
          testAdd(NumberType.fp32, 2.0, 2.0, 4.0);
          testAdd(NumberType.fp64, 2.0, -2.5, -0.5);
        });
      });

      group('sub', () {
        var testSub = (NumberType numberType, num op1, num op2, num result) =>
            testArithmetic(
                new SubtractInstruction(numberType), op1, op2, result);

        group('<uint>', () {
          test('subtracts values', () {
            testSub(NumberType.uint8, 12, 11, 1);
            testSub(NumberType.uint64, 1 << 33, 1 << 33, 0);
          });

          test('overflows', () {
            testSub(NumberType.uint8, 11, 12, 255);
          });
        });

        group('<sint>', () {
          test('subtracts values', () {
            testSub(NumberType.sint8, -5, 3, -8);
            testSub(NumberType.sint64, -(1 << 40), -(1 << 40), 0);
          });

          test('overflows', () {
            testSub(NumberType.sint8, 2, 131, 127);
          });
        });

        test('<float> subtracts values', () {
          testSub(NumberType.fp32, 8.0, -4.0, 12.0);
          testSub(NumberType.fp64, 3.25, 1.75, 1.5);
        });
      });

      group('mul', () {
        var testMul = (NumberType numberType, num op1, num op2, num result) =>
            testArithmetic(
                new MultiplyInstruction(numberType), op1, op2, result);

        group('<uint>', () {
          test('multiplies values', () {
            testMul(NumberType.uint8, 8, 9, 72);
            testMul(NumberType.uint64, 1 << 30, 1 << 10, 1 << 40);
          });

          test('overflows', () {
            testMul(NumberType.uint8, 100, 100, 16);
          });
        });

        group('<sint>', () {
          test('multiplies values', () {
            testMul(NumberType.sint8, -7, -6, 42);
            testMul(NumberType.sint64, 1 << 40, -2, -(1 << 41));
          });

          test('overflows', () {
            testMul(NumberType.sint8, 12, 12, -112);
          });
        });

        test('<float> multiplies values', () {
          testMul(NumberType.fp32, 0.5, -0.5, -0.25);
          testMul(NumberType.fp64, PI, LN2, PI * LN2);
        });
      });

      group('div', () {
        var testDiv = (NumberType numberType, num op1, num op2, num result) =>
            testArithmetic(new DivideInstruction(numberType), op1, op2, result);

        group('<uint>', () {
          test('divides values', () {
            testDiv(NumberType.uint8, 10, 2, 5);
            testDiv(NumberType.uint64, 1 << 45, 4, 1 << 43);
          });

          test('rounds down', () {
            testDiv(NumberType.uint32, 100000, 30000, 3);
          });
        });

        test('<sint> divides values', () {
          testDiv(NumberType.sint8, -21, 3, -7);
        });

        test('<float> divides values', () {
          testDiv(NumberType.fp32, 64, 32, 2);
          testDiv(NumberType.fp64, 19, 10, 1.9);
        });
      });

      group('mod', () {
        var testMod = (NumberType numberType, num op1, num op2, num result) =>
            testArithmetic(new ModuloInstruction(numberType), op1, op2, result);

        test('<uint> calculates remainder', () {
          testMod(NumberType.uint8, 147, 12, 3);
          testMod(NumberType.uint64, (1 << 45) + 1, 2, 1);
        });

        test('<sint> calculates remainder', () {
          testMod(NumberType.sint8, 69, -16, 5);
        });
      });

      group('and', () {
        var testAnd =
            (NumberType numberType, String op1, String op2, String result) =>
                testArithmetic(
                    new BitwiseAndInstruction(numberType),
                    int.parse(op1, radix: 2),
                    int.parse(op2, radix: 2),
                    int.parse(result, radix: 2));

        test('calculates bitwise and', () {
          testAnd(NumberType.uint8, '10101010', '00001111', '00001010');
          testAnd(
              NumberType.uint64,
              '1111000011110000111100001111000011110000111100001111000011110000',
              '1010010001000010000010000001000000010000000010000000001000000000',
              '1010000001000000000000000001000000010000000000000000000000000000');
        });
      });

      group('or', () {
        var testOr =
            (NumberType numberType, String op1, String op2, String result) =>
                testArithmetic(
                    new BitwiseOrInstruction(numberType),
                    int.parse(op1, radix: 2),
                    int.parse(op2, radix: 2),
                    int.parse(result, radix: 2));

        test('calculates bitwise and', () {
          testOr(NumberType.uint8, '10101010', '00001111', '10101111');
          testOr(
              NumberType.uint64,
              '1111000011110000111100001111000011110000111100001111000011110000',
              '1010010001000010000010000001000000010000000010000000001000000000',
              '1111010011110010111110001111000011110000111110001111001011110000');
        });
      });

      group('xor', () {
        var testXor =
            (NumberType numberType, String op1, String op2, String result) =>
                testArithmetic(
                    new BitwiseExclusiveOrInstruction(numberType),
                    int.parse(op1, radix: 2),
                    int.parse(op2, radix: 2),
                    int.parse(result, radix: 2));

        test('calculates bitwise and', () {
          testXor(NumberType.uint8, '10101010', '00001111', '10100101');
          testXor(
              NumberType.uint64,
              '1111000011110000111100001111000011110000111100001111000011110000',
              '1010010001000010000010000001000000010000000010000000001000000000',
              '0101010010110010111110001110000011100000111110001111001011110000');
        });
      });
    });

    group('comparison:', () {
      var compare = (ComparisonInstruction instruction, num op1, num op2) {
        vm.pushStack(instruction.valueType, op1);
        vm.pushStack(instruction.valueType, op2);
        encodeInstruction(instruction);
        vm.executeNextInstruction();
        return vm.popStack(NumberType.uint8) > 0;
      };

      group('eq', () {
        var compareEq = (NumberType numberType, num op1, num op2) =>
            compare(new EqualsInstruction(numberType), op1, op2);

        test('<uint>', () {
          expect(compareEq(NumberType.uint8, 42, 42), isTrue);
          expect(compareEq(NumberType.uint8, 5, 0), isFalse);
          expect(compareEq(NumberType.uint64, 1 << 63, 1 << 63), isTrue);
        });

        test('<sint>', () {
          expect(compareEq(NumberType.sint8, -120, -120), isTrue);
          expect(compareEq(NumberType.sint8, -100, 100), isFalse);
          expect(compareEq(NumberType.sint64, -(1 << 50), -(1 << 50)), isTrue);
        });

        test('<float>', () {
          expect(compareEq(NumberType.fp32, 123.7, 123.7), isTrue);
          expect(compareEq(NumberType.fp32, .0, -.0), isTrue);
          expect(compareEq(NumberType.fp32, 123.7, 123.8), isFalse);
          expect(compareEq(NumberType.fp32, double.NAN, double.NAN), isFalse);
        });

        test('<double>', () {
          expect(compareEq(NumberType.fp64, PI, PI), isTrue);
          expect(compareEq(NumberType.fp64, .0, -.0), isTrue);
          expect(compareEq(NumberType.fp64, double.NAN, double.NAN), isFalse);
        });
      });

      group('gt', () {
        var compareGt = (NumberType numberType, num op1, num op2) =>
            compare(new GreaterThanInstruction(numberType), op1, op2);

        test('<uint>', () {
          expect(compareGt(NumberType.uint8, 5, 3), isTrue);
          expect(compareGt(NumberType.uint8, 3, 5), isFalse);
          expect(compareGt(NumberType.uint8, 3, 3), isFalse);
        });

        test('<sint>', () {
          expect(compareGt(NumberType.sint8, -99, -100), isTrue);
          expect(compareGt(NumberType.sint8, -100, 99), isFalse);
        });

        test('<float>', () {
          expect(compareGt(NumberType.fp32, .001, .0001), isTrue);
          expect(compareGt(NumberType.fp32, double.INFINITY, 5), isTrue);
          expect(compareGt(NumberType.fp32, 8, 12), isFalse);
          expect(compareGt(NumberType.fp32, double.NAN, double.NAN), isFalse);
        });

        test('<double>', () {
          expect(compareGt(NumberType.fp64, -1000, double.NEGATIVE_INFINITY),
              isTrue);
          expect(compareGt(NumberType.fp64, double.INFINITY, double.INFINITY),
              isFalse);
          expect(compareGt(NumberType.fp64, double.NAN, double.NAN), isFalse);
        });
      });

      group('ge', () {
        var compareGe = (NumberType numberType, num op1, num op2) =>
            compare(new GreaterEqualsInstruction(numberType), op1, op2);

        test('<uint>', () {
          expect(compareGe(NumberType.uint8, 6, 2), isTrue);
          expect(compareGe(NumberType.uint8, 2, 6), isFalse);
          expect(compareGe(NumberType.uint8, 2, 2), isTrue);
        });

        test('<sint>', () {
          expect(compareGe(NumberType.sint8, -7, -100), isTrue);
          expect(compareGe(NumberType.sint8, -7, -7), isTrue);
        });

        test('<float>', () {
          expect(compareGe(NumberType.fp32, .001, .0001), isTrue);
          expect(compareGe(NumberType.fp32, .001, .001), isTrue);
          expect(compareGe(NumberType.fp32, .001, .01), isFalse);
        });

        test('<double>', () {
          expect(compareGe(NumberType.fp64, 50, 45), isTrue);
          expect(compareGe(NumberType.fp64, double.NAN, double.NAN), isFalse);
        });
      });
    });

    group('not', () {
      test('toggles between 0 and 1', () {
        vm.pushStack(NumberType.uint8, 0);
        encodeInstruction(new ToggleBooleanInstruction());
        encodeInstruction(new ToggleBooleanInstruction());

        vm.executeNextInstruction();
        expect(
            vm.readMemoryValue(vm.stackPointer, NumberType.uint8), equals(1));
        vm.executeNextInstruction();
        expect(
            vm.readMemoryValue(vm.stackPointer, NumberType.uint8), equals(0));
      });

      test('recognizes non-zero values as true', () {
        vm.pushStack(NumberType.uint8, 123);
        encodeInstruction(new ToggleBooleanInstruction());
        vm.executeNextInstruction();
        expect(
            vm.readMemoryValue(vm.stackPointer, NumberType.uint8), equals(0));
      });
    });
  });
}
