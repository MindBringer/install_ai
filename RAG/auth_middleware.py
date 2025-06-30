from fastapi import Request, HTTPException, Depends
from fastapi.security import HTTPBearer
from jose import jwt, JWTError
import httpx, os

OIDC_ISSUER = os.getenv("OIDC_ISSUER")  # z.B. https://login.microsoftonline.com/<tenant_id>/v2.0
OIDC_CLIENT_ID = os.getenv("OIDC_CLIENT_ID")
JWKS_URL = f"{OIDC_ISSUER}/discovery/v2.0/keys"

auth_scheme = HTTPBearer()
cached_keys = None

async def get_user_context(request: Request, credentials=Depends(auth_scheme)):
    global cached_keys
    token = credentials.credentials

    # JWKS laden (einmalig cachen)
    if not cached_keys:
        async with httpx.AsyncClient() as client:
            r = await client.get(JWKS_URL)
            cached_keys = r.json()

    try:
        unverified_header = jwt.get_unverified_header(token)
        key = next(k for k in cached_keys["keys"] if k["kid"] == unverified_header["kid"])
        user = jwt.decode(
            token,
            key,
            algorithms=["RS256"],
            audience=OIDC_CLIENT_ID,
            issuer=OIDC_ISSUER
        )
        return {
            "email": user.get("preferred_username") or user.get("email"),
            "groups": user.get("groups", [])
        }
    except JWTError as e:
        raise HTTPException(status_code=401, detail=f"Invalid token: {str(e)}")