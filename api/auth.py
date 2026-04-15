import os
from typing import Annotated

import firebase_admin
from firebase_admin import auth as fb_auth, credentials
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

# Initialise Firebase Admin SDK once at import time.
# Set GOOGLE_APPLICATION_CREDENTIALS env var to the path of your service account JSON,
# or set FIREBASE_CREDENTIALS_JSON to the JSON content directly.
_cred_json = os.environ.get("FIREBASE_CREDENTIALS_JSON")
if _cred_json:
    import json, tempfile, pathlib
    _tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False, mode="w")
    _tmp.write(_cred_json)
    _tmp.close()
    _cred = credentials.Certificate(_tmp.name)
else:
    _cred = credentials.ApplicationDefault()

if not firebase_admin._apps:
    firebase_admin.initialize_app(_cred)

bearer_scheme = HTTPBearer()


async def get_current_user(
    creds: Annotated[HTTPAuthorizationCredentials, Depends(bearer_scheme)],
) -> dict:
    try:
        decoded = fb_auth.verify_id_token(creds.credentials)
        return decoded
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired Firebase token",
        )
