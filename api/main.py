from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from api.db import init_db
from api.routers import allowances, trips, users, messages, declarations, ratings


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    yield


app = FastAPI(title="BlaBlaCase API", version="0.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    # GitHub Pages origin will be added here once the repo name is known.
    # For development allow all origins; tighten before production.
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(allowances.router, prefix="/allowances", tags=["allowances"])
app.include_router(trips.router, prefix="/trips", tags=["trips"])
app.include_router(users.router, prefix="/users", tags=["users"])
app.include_router(messages.router, tags=["messages"])
app.include_router(declarations.router, tags=["declarations"])
app.include_router(ratings.router, prefix="/ratings", tags=["ratings"])


@app.get("/health")
async def health():
    return {"status": "ok"}
