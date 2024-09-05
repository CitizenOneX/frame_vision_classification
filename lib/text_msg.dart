import 'dart:convert';

class TextMsg {
  static const textMsgType = 0x0a;

  static List<int> pack(String text) {
    int lengthMsb = (text.length) >> 8 & 0xFF;
    int lengthLsb = (text.length) & 0xFF;

    // data byte 0x01, MSG_TYPE 0x0d, msg_length(Uint16), the bytes of the string in utf8
    return [0x01, textMsgType, lengthMsb, lengthLsb, ...utf8.encode(text)];
  }
}
