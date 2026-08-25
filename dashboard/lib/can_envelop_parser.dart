import 'can_frame.dart';

class CanEnvelopeParser {
  static const int startDelimiter = 0xAA;
  static const int endDelimiter = 0x55;

  _ParserState _state = _ParserState.waitingForStart;

  int _frameInfo = 0;
  bool _isExtended = false;
  int _dlc = 0;

  final List<int> _frameBytes = [];  //this is the list which will hold the incoming bytes of the frame until we have a complete frame to parse
  int _expectedFrameLength = 0;

  List<CanFrame> feed(List<int> bytes) {    //this is the main function which will be called from the serial reader and udp reader to parse the incoming bytes and return a list of CanFrame objects
  //here feed is the method name the method that is used feed the incoming bytes to the parser
    final frames = <CanFrame>[];  // it holds the complete one frame created at the end of this method

    for (final byte in bytes) {
      final frame = _processByte(byte);
      if (frame != null) {
        frames.add(frame);
      }
    }

    return frames;
  }

  CanFrame? _processByte(int byte) {    //starts processing the incoming byte and returns a CanFrame object if a complete frame is found, otherwise returns null
    switch (_state) {
      case _ParserState.waitingForStart:
        if (byte == startDelimiter) {
          _frameBytes.clear();
          _frameBytes.add(byte);
          _state = _ParserState.readingFrameInfo;
        }
        return null;

      case _ParserState.readingFrameInfo:
        _frameInfo = byte;
        _frameBytes.add(byte);

        // Bit 5: 0 = Standard 11-bit ID, 1 = Extended 29-bit ID
        _isExtended = (_frameInfo & 0x20) != 0; //0x20 = 0010 0000

        // Bits 3-0: DLC (0..8)
        _dlc = _frameInfo & 0x0F;   //DLC here is DATA Length Code tells the exact size of the payload
//DLC is extracted from the 0-3 thats 4 bits of the frameInfo Byte
        if (_dlc > 8) {
          _reset();
          return null;
        }

        final idLength = _isExtended ? 4 : 2;
        _expectedFrameLength = 1 + 1 + idLength + _dlc + 1;
        _state = _ParserState.readingRest;
        return null;

      case _ParserState.readingRest:    //continues until all the bytes are taken according to the length
        _frameBytes.add(byte);

        if (_frameBytes.length == _expectedFrameLength) {
          return _finishFrame();
        }

        if (_frameBytes.length > _expectedFrameLength) {
          _reset();
        }

        return null;
    }
  }

  CanFrame? _finishFrame() {
    if (_frameBytes.last != endDelimiter) {
      _reset();
      return null;
    }

    const idStart = 2;
    final idLength = _isExtended ? 4 : 2;
    int canId = 0;

    // Little-Endian CAN ID calculation
    for (int i = 0; i < idLength; i++) {
      canId |= _frameBytes[idStart + i] << (8 * i);
    }

    if (!_isExtended) {
      canId &= 0x7FF;       //7FF = 011111111111
    } else {
      canId &= 0x1FFFFFFF;    //1FFFFFFF = 00011111111111111111111111111111 
    }

    final payloadStart = idStart + idLength;
    final payloadEnd = payloadStart + _dlc;
    final payload = List<int>.from(_frameBytes.sublist(payloadStart, payloadEnd));

    final result = CanFrame(      //for constucting the object and parsing the date and time 
      canId: canId,
      isExtended: _isExtended,
      dlc: _dlc,
      data: payload,
      frameInfo: _frameInfo,
    );

    _reset();
    return result;
  }

  void _reset() {
    _state = _ParserState.waitingForStart;
    _frameBytes.clear();
    _frameInfo = 0;
    _isExtended = false;
    _dlc = 0;
    _expectedFrameLength = 0;
  }
}

enum _ParserState {
  waitingForStart,
  readingFrameInfo,
  readingRest,
}