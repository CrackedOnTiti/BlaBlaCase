import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from api.auth import get_current_user
from api.db import get_db
from api.models import User

router = APIRouter()


class UserOut(BaseModel):
    id: uuid.UUID
    display_name: str
    avatar_url: str | None
    avg_rating: float
    rating_count: int

    model_config = {"from_attributes": True}


# Extended schema for the authenticated user's own profile (includes phone)
class MyUserOut(UserOut):
    phone: str


class UserUpdate(BaseModel):
    display_name: str | None = None
    avatar_url: str | None = None


async def get_or_create_user(firebase_user: dict, db: AsyncSession) -> User:
    uid = firebase_user["uid"]
    result = await db.execute(select(User).where(User.firebase_uid == uid))
    user = result.scalar_one_or_none()
    if user is None:
        phone = firebase_user.get("phone_number", "")
        user = User(
            firebase_uid=uid,
            phone=phone,
            display_name=firebase_user.get("name") or phone or "Utilisateur",
        )
        db.add(user)
        await db.commit()
        await db.refresh(user)
    return user


@router.get("/me", response_model=MyUserOut)
async def get_me(
    firebase_user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    return await get_or_create_user(firebase_user, db)


@router.patch("/me", response_model=MyUserOut)
async def update_me(
    body: UserUpdate,
    firebase_user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    user = await get_or_create_user(firebase_user, db)
    if body.display_name is not None:
        user.display_name = body.display_name
    if body.avatar_url is not None:
        user.avatar_url = body.avatar_url
    await db.commit()
    await db.refresh(user)
    return user


@router.delete("/me", status_code=status.HTTP_204_NO_CONTENT)
async def delete_me(
    firebase_user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    user = await get_or_create_user(firebase_user, db)
    await db.delete(user)
    await db.commit()


@router.get("/{user_id}", response_model=UserOut)
async def get_user(user_id: uuid.UUID, db: Annotated[AsyncSession, Depends(get_db)]):
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    return user
