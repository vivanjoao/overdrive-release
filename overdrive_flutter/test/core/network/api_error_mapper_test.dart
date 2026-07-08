import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:overdrive_flutter/core/network/api_error_mapper.dart';
import 'package:overdrive_flutter/core/result/result.dart';

void main() {
  group('DioException.toAppError', () {
    test('connectionTimeout → NetworkError', () {
      final e = DioException(requestOptions: RequestOptions(), type: DioExceptionType.connectionTimeout);
      final err = e.toAppError();
      expect(err, isA<NetworkError>());
      expect(err.message.toLowerCase(), contains('timed out'));
    });

    test('receiveTimeout → NetworkError', () {
      final e = DioException(requestOptions: RequestOptions(), type: DioExceptionType.receiveTimeout);
      expect(e.toAppError(), isA<NetworkError>());
    });

    test('sendTimeout → NetworkError', () {
      final e = DioException(requestOptions: RequestOptions(), type: DioExceptionType.sendTimeout);
      expect(e.toAppError(), isA<NetworkError>());
    });

    test('connectionError → NetworkError (cleaned up)', () {
      final e = DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.connectionError,
        error: 'Failed to fetch: DNS resolution failed',
      );
      final err = e.toAppError();
      expect(err, isA<NetworkError>());
      // "Failed to fetch" wrapper is replaced with a friendlier message.
      expect(err.message, isNot(contains('Failed to fetch')));
      expect(err.message.toLowerCase(), contains('head unit'));
    });

    test('badResponse 404 → NotFoundError', () {
      final e = DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(),
          statusCode: 404,
        ),
      );
      final err = e.toAppError();
      expect(err, isA<NotFoundError>());
      expect(err.message.toLowerCase(), contains('not found'));
    });

    test('badResponse 5xx → HttpError with status code', () {
      final e = DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(),
          statusCode: 503,
        ),
      );
      final err = e.toAppError();
      expect(err, isA<HttpError>());
      expect((err as HttpError).statusCode, 503);
    });

    test('badResponse 4xx (non-404) → HttpError with status code', () {
      final e = DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(),
          statusCode: 422,
        ),
      );
      final err = e.toAppError();
      expect(err, isA<HttpError>());
      expect((err as HttpError).statusCode, 422);
    });

    test('cancel → UnexpectedError', () {
      final e = DioException(requestOptions: RequestOptions(), type: DioExceptionType.cancel);
      expect(e.toAppError(), isA<UnexpectedError>());
    });

    test('unknown → UnexpectedError, preserves underlying message', () {
      final e = DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.unknown,
        error: 'something bizarre',
      );
      final err = e.toAppError();
      expect(err, isA<UnexpectedError>());
      expect(err.message, contains('something bizarre'));
    });

    test('badCertificate → NetworkError', () {
      final e = DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.badCertificate,
      );
      expect(e.toAppError(), isA<NetworkError>());
    });

    test('long socket traces are truncated', () {
      final longMsg = 'A' * 500;
      final e = DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.connectionError,
        error: longMsg,
      );
      final err = e.toAppError() as NetworkError;
      expect(err.message.length, lessThanOrEqualTo(120));
    });
  });

  group('AppError hierarchy', () {
    test('subclasses preserve their type identity through toString', () {
      expect(const NetworkError('x').toString(), 'NetworkError(x)');
      expect(const UnexpectedError('y').toString(), 'UnexpectedError(y)');
    });

    test('HttpError exposes statusCode', () {
      const e = HttpError('boom', statusCode: 502);
      expect(e.statusCode, 502);
    });
  });
}
