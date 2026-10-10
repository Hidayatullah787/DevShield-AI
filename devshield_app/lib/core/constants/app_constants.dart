class AppConstants {
  static const String appName = 'DevShield AI';
  static const String appTagline = 'From production error to evidence-backed fix.';
  static const String defaultBaseUrl = 'http://127.0.0.1:8000';

  // Sample Data Scenarios for Quick Demos
  static const String sampleCheckoutLogs = '''{"timestamp":"2026-03-20T10:00:00Z","service":"checkout","severity":"ERROR","message":"Database connection pool timeout while acquiring connection to read replica","trace_id":"chk-9912","metadata":{"env":"production"}}
{"timestamp":"2026-03-20T10:00:45Z","service":"checkout","severity":"ERROR","message":"Active connections exceeded pool maximum. Pool size: 5, pending requests: 84","trace_id":"chk-9915","metadata":{"env":"production"}}
{"timestamp":"2026-03-20T10:01:20Z","service":"checkout","severity":"CRITICAL","message":"ConnectionPoolExhaustedException: HTTP 503 Service Unavailable for /v1/checkout/pay","trace_id":"chk-9920","metadata":{"env":"production"}}
{"timestamp":"2026-03-20T10:02:00Z","service":"checkout","severity":"WARN","message":"Retry circuit breaker tripped after 3 consecutive connection timeouts","trace_id":"chk-9930","metadata":{"env":"production"}}''';

  static const String sampleCheckoutDiff = '''diff --git a/services/checkout/db_config.py b/services/checkout/db_config.py
index a41bc90..7fd3a12 100644
--- a/services/checkout/db_config.py
+++ b/services/checkout/db_config.py
@@ -14,6 +14,6 @@ class DatabasePoolConfig:
-    POOL_TIMEOUT_SECONDS = 30
-    MAX_CONNECTIONS = 50
-    IDLE_TIMEOUT_SECONDS = 300
+    POOL_TIMEOUT_SECONDS = 2
+    MAX_CONNECTIONS = 5
+    IDLE_TIMEOUT_SECONDS = 30
''';

  static const String sampleAuthLogs = '''{"timestamp":"2026-03-20T14:15:00Z","service":"auth","severity":"ERROR","message":"JWT token signature valid but token expired immediately after minting","trace_id":"auth-331","metadata":{"env":"production"}}
{"timestamp":"2026-03-20T14:16:00Z","service":"auth","severity":"CRITICAL","message":"High volume of authentication failures (HTTP 401) on /oauth/token endpoint","trace_id":"auth-340","metadata":{"env":"production"}}''';

  static const String sampleAuthDiff = '''diff --git a/services/auth/tokens.py b/services/auth/tokens.py
index b8912e1..44f12ab 100644
--- a/services/auth/tokens.py
+++ b/services/auth/tokens.py
@@ -8,3 +8,3 @@ def mint_session_token(user_id: str) -> str:
-    TOKEN_TTL_SECONDS = 3600
+    TOKEN_TTL_SECONDS = 5
''';
}

