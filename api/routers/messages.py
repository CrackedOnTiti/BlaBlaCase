import uuid
from datetime import datetime, timedelta, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import and_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from api.auth import get_current_user
from api.db import get_db
from api.models import Message, Trip, TripPassenger
from api.routers.users import UserOut, get_or_create_user

router = APIRouter()

MESSAGE_TTL_HOURS = 72


class MessageCreate(BaseModel):
    content: str


class MessageOut(BaseModel):
    id: uuid.UUID
    sender: UserOut
    content: str
    created_at: datetime

    model_config = {"from_attributes": True}


async def _assert_trip_member(trip_id: uuid.UUID, user_id: uuid.UUID, db: AsyncSession):
    """Raises 403 if the user is not the driver or an accepted passenger."""
    result = await db.execute(select(Trip).where(Trip.id == trip_id))
    trip = result.scalar_one_or_none()
    if not trip:
        raise HTTPException(status_code=404, detail="Trip not found")

    if trip.driver_id == user_id:
        return  # driver always has access

    member = await db.execute(
        select(TripPassenger).where(
            and_(
                TripPassenger.trip_id == trip_id,
                TripPassenger.user_id == user_id,
                TripPassenger.status == "accepted",
            )
        )
    )
    if not member.scalar_one_or_none():
        raise HTTPException(status_code=403, detail="You are not a member of this trip")


@router.get("/trips/{trip_id}/messages", response_model=list[MessageOut])
async def get_messages(
    trip_id: uuid.UUID,
    firebase_user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    user = await get_or_create_user(firebase_user, db)
    await _assert_trip_member(trip_id, user.id, db)

    cutoff = datetime.now(timezone.utc) - timedelta(hours=MESSAGE_TTL_HOURS)
    result = await db.execute(
        select(Message)
        .options(selectinload(Message.sender))
        .where(and_(Message.trip_id == trip_id, Message.created_at >= cutoff))
        .order_by(Message.created_at)
        .limit(200)
    )
    return result.scalars().all()


@router.post("/trips/{trip_id}/messages", response_model=MessageOut, status_code=201)
async def send_message(
    trip_id: uuid.UUID,
    body: MessageCreate,
    firebase_user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    user = await get_or_create_user(firebase_user, db)
    await _assert_trip_member(trip_id, user.id, db)

    if not body.content.strip():
        raise HTTPException(status_code=400, detail="Message content cannot be empty")

    msg = Message(trip_id=trip_id, sender_id=user.id, content=body.content.strip())
    db.add(msg)
    await db.commit()

    result = await db.execute(
        select(Message).options(selectinload(Message.sender)).where(Message.id == msg.id)
    )
    return result.scalar_one()
