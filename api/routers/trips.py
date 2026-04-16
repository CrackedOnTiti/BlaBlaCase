import uuid
from datetime import datetime, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, model_validator
from sqlalchemy import and_, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from api.auth import get_current_user
from api.db import get_db
from api.models import Message, Trip, TripPassenger, User
from api.routers.users import UserOut, get_or_create_user

router = APIRouter()


# ── Schemas ──────────────────────────────────────────────────────────────────

class TripCreate(BaseModel):
    departure_city: str
    departure_lat: float
    departure_lng: float
    depart_at: datetime
    return_at: datetime
    seats_total: int
    notes: str | None = None

    @model_validator(mode="after")
    def validate_dates(self):
        if self.return_at <= self.depart_at:
            raise ValueError("return_at must be after depart_at")
        if self.seats_total < 1 or self.seats_total > 8:
            raise ValueError("seats_total must be between 1 and 8")
        return self


class PassengerOut(BaseModel):
    user: UserOut
    status: str

    model_config = {"from_attributes": True}


class TripOut(BaseModel):
    id: uuid.UUID
    driver: UserOut
    departure_city: str
    departure_lat: float
    departure_lng: float
    depart_at: datetime
    return_at: datetime
    seats_total: int
    seats_available: int
    notes: str | None
    status: str
    created_at: datetime
    passengers: list[PassengerOut] = []

    model_config = {"from_attributes": True}


class PassengerStatusUpdate(BaseModel):
    status: str  # accepted | rejected


class JoinRequest(BaseModel):
    intro_message: str | None = None


class TripRoomOut(BaseModel):
    trip_id: uuid.UUID
    departure_city: str
    depart_at: datetime
    last_message_content: str | None
    last_message_at: datetime | None
    last_message_sender: str | None
    user_has_messaged: bool = False

    model_config = {"from_attributes": True}


class PendingRequestOut(BaseModel):
    trip_id: uuid.UUID
    departure_city: str
    depart_at: datetime
    passenger: UserOut
    intro_message: str | None

    model_config = {"from_attributes": True}


# ── Helpers ──────────────────────────────────────────────────────────────────

async def _load_trip(trip_id: uuid.UUID, db: AsyncSession) -> Trip:
    result = await db.execute(
        select(Trip)
        .options(
            selectinload(Trip.driver),
            selectinload(Trip.passengers).selectinload(TripPassenger.user),
        )
        .where(Trip.id == trip_id)
    )
    trip = result.scalar_one_or_none()
    if not trip:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Trip not found")
    return trip


# ── Routes ───────────────────────────────────────────────────────────────────

@router.post("", response_model=TripOut, status_code=status.HTTP_201_CREATED)
async def create_trip(
    body: TripCreate,
    firebase_user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    user = await get_or_create_user(firebase_user, db)
    trip = Trip(
        driver_id=user.id,
        departure_city=body.departure_city,
        departure_lat=body.departure_lat,
        departure_lng=body.departure_lng,
        depart_at=body.depart_at,
        return_at=body.return_at,
        seats_total=body.seats_total,
        seats_available=body.seats_total,
        notes=body.notes,
    )
    db.add(trip)
    await db.commit()
    return await _load_trip(trip.id, db)


@router.get("", response_model=list[TripOut])
async def list_trips(
    db: Annotated[AsyncSession, Depends(get_db)],
    city: str | None = Query(None),
    date_from: datetime | None = Query(None),
    date_to: datetime | None = Query(None),
    limit: int = Query(50, le=100),
    offset: int = Query(0),
):
    q = (
        select(Trip)
        .options(
            selectinload(Trip.driver),
            selectinload(Trip.passengers).selectinload(TripPassenger.user),
        )
        .where(Trip.status == "open")
        .order_by(Trip.depart_at)
        .limit(limit)
        .offset(offset)
    )
    if city:
        q = q.where(Trip.departure_city.ilike(f"%{city}%"))
    if date_from:
        q = q.where(Trip.depart_at >= date_from)
    if date_to:
        q = q.where(Trip.depart_at <= date_to)

    result = await db.execute(q)
    return result.scalars().all()


@router.get("/mine", response_model=list[TripRoomOut])
async def get_my_trips(
    firebase_user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    user = await get_or_create_user(firebase_user, db)

    # Trips where user is driver
    driver_q = select(Trip.id).where(Trip.driver_id == user.id)
    # Trips where user is accepted passenger
    passenger_q = select(TripPassenger.trip_id).where(
        and_(TripPassenger.user_id == user.id, TripPassenger.status == "accepted")
    )

    result = await db.execute(
        select(Trip)
        .where(or_(Trip.id.in_(driver_q), Trip.id.in_(passenger_q)))
        .where(Trip.status != "cancelled")
        .order_by(Trip.depart_at)
    )
    trips = result.scalars().all()

    rooms = []
    for trip in trips:
        msg_result = await db.execute(
            select(Message)
            .options(selectinload(Message.sender))
            .where(Message.trip_id == trip.id)
            .order_by(Message.created_at.desc())
            .limit(1)
        )
        last_msg = msg_result.scalar_one_or_none()
        user_msg_result = await db.execute(
            select(Message.id)
            .where(and_(Message.trip_id == trip.id, Message.sender_id == user.id))
            .limit(1)
        )
        user_has_messaged = user_msg_result.scalar_one_or_none() is not None
        rooms.append(TripRoomOut(
            trip_id=trip.id,
            departure_city=trip.departure_city,
            depart_at=trip.depart_at,
            last_message_content=last_msg.content if last_msg else None,
            last_message_at=last_msg.created_at if last_msg else None,
            last_message_sender=last_msg.sender.display_name if last_msg else None,
            user_has_messaged=user_has_messaged,
        ))
    rooms.sort(
        key=lambda r: r.last_message_at or datetime.min.replace(tzinfo=timezone.utc),
        reverse=True,
    )
    return rooms


@router.get("/mine/full", response_model=list[TripOut])
async def get_my_trips_full(
    firebase_user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    user = await get_or_create_user(firebase_user, db)
    driver_q = select(Trip.id).where(Trip.driver_id == user.id)
    passenger_q = select(TripPassenger.trip_id).where(
        and_(TripPassenger.user_id == user.id, TripPassenger.status == "accepted")
    )
    result = await db.execute(
        select(Trip)
        .options(
            selectinload(Trip.driver),
            selectinload(Trip.passengers).selectinload(TripPassenger.user),
        )
        .where(or_(Trip.id.in_(driver_q), Trip.id.in_(passenger_q)))
        .where(Trip.status != "cancelled")
        .order_by(Trip.depart_at)
    )
    return result.scalars().all()


@router.get("/notifications", response_model=list[PendingRequestOut])
async def get_notifications(
    firebase_user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    user = await get_or_create_user(firebase_user, db)
    result = await db.execute(
        select(TripPassenger)
        .join(Trip, TripPassenger.trip_id == Trip.id)
        .options(selectinload(TripPassenger.user), selectinload(TripPassenger.trip))
        .where(and_(Trip.driver_id == user.id, TripPassenger.status == "pending"))
        .order_by(TripPassenger.joined_at)
    )
    rows = result.scalars().all()
    return [
        PendingRequestOut(
            trip_id=r.trip_id,
            departure_city=r.trip.departure_city,
            depart_at=r.trip.depart_at,
            passenger=r.user,
            intro_message=r.intro_message,
        )
        for r in rows
    ]


@router.get("/{trip_id}", response_model=TripOut)
async def get_trip(trip_id: uuid.UUID, db: Annotated[AsyncSession, Depends(get_db)]):
    return await _load_trip(trip_id, db)


@router.post("/{trip_id}/join", status_code=status.HTTP_201_CREATED)
async def join_trip(
    trip_id: uuid.UUID,
    body: JoinRequest,
    firebase_user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    user = await get_or_create_user(firebase_user, db)
    trip = await _load_trip(trip_id, db)

    if trip.driver_id == user.id:
        raise HTTPException(status_code=400, detail="You are the driver of this trip")
    if trip.seats_available <= 0:
        raise HTTPException(status_code=400, detail="No seats available")
    if trip.status != "open":
        raise HTTPException(status_code=400, detail="Trip is not open")

    existing = await db.execute(
        select(TripPassenger).where(
            and_(TripPassenger.trip_id == trip_id, TripPassenger.user_id == user.id)
        )
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Already joined this trip")

    participation = TripPassenger(
        trip_id=trip_id,
        user_id=user.id,
        intro_message=body.intro_message.strip() if body.intro_message else None,
    )
    db.add(participation)
    await db.commit()
    return {"detail": "Join request sent"}


@router.patch("/{trip_id}/passengers/{user_id}", response_model=TripOut)
async def update_passenger_status(
    trip_id: uuid.UUID,
    user_id: uuid.UUID,
    body: PassengerStatusUpdate,
    firebase_user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    driver = await get_or_create_user(firebase_user, db)
    trip = await _load_trip(trip_id, db)

    if trip.driver_id != driver.id:
        raise HTTPException(status_code=403, detail="Only the driver can accept/reject passengers")
    if body.status not in ("accepted", "rejected"):
        raise HTTPException(status_code=400, detail="status must be 'accepted' or 'rejected'")

    result = await db.execute(
        select(TripPassenger).where(
            and_(TripPassenger.trip_id == trip_id, TripPassenger.user_id == user_id)
        )
    )
    participation = result.scalar_one_or_none()
    if not participation:
        raise HTTPException(status_code=404, detail="Passenger not found")

    previous_status = participation.status
    participation.status = body.status

    # Update seat count
    if body.status == "accepted" and previous_status != "accepted":
        trip.seats_available = max(0, trip.seats_available - 1)
        if trip.seats_available == 0:
            trip.status = "full"
        # Auto-message in group chat
        passenger_result = await db.execute(select(User).where(User.id == user_id))
        passenger = passenger_result.scalar_one_or_none()
        if passenger:
            name = passenger.display_name or "Quelqu'un"
            db.add(Message(
                trip_id=trip_id,
                sender_id=user_id,
                content=f"👋 {name} a rejoint le trajet ! Dites-lui bonjour 😄",
            ))
    elif body.status == "rejected" and previous_status == "accepted":
        trip.seats_available = min(trip.seats_total, trip.seats_available + 1)
        trip.status = "open"

    await db.commit()
    return await _load_trip(trip_id, db)


@router.delete("/{trip_id}", status_code=status.HTTP_204_NO_CONTENT)
async def cancel_trip(
    trip_id: uuid.UUID,
    firebase_user: Annotated[dict, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    driver = await get_or_create_user(firebase_user, db)
    trip = await _load_trip(trip_id, db)
    if trip.driver_id != driver.id:
        raise HTTPException(status_code=403, detail="Only the driver can cancel the trip")
    trip.status = "cancelled"
    await db.commit()
