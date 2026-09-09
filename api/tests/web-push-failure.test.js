const test = require('node:test');
const assert = require('node:assert/strict');
const { webPushFailureCode } = require('../dist/src/services/notification.service');

test('Apple key mismatches retain the actionable provider reason', () => {
  assert.equal(webPushFailureCode({statusCode: 400, body: '{"reason":"VapidPkHashMismatch"}'}),
    'HTTP_400_VapidPkHashMismatch');
});

test('HTML and malformed responses retain the HTTP code without response data', () => {
  for (const body of ['<html>error</html>', '{', '{"reason":"token: private data"}']) {
    assert.equal(webPushFailureCode({statusCode: 401, body}), 'HTTP_401');
  }
  assert.equal(webPushFailureCode(new Error('offline')), 'DELIVERY_FAILED');
});
