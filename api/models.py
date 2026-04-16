"""SQLAlchemy ORM models — all tables in one file for clarity at this stage."""
import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    BigInteger, Boolean, CheckConstraint, DateTime, Float, ForeignKey,
    Integer, String, Text, UniqueConstraint, func,
)
from sqlalchemy.sql import expression
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from api.db import Base


def _now() -> datetime:
    return datetime.now(timezone.utc)


# ── Users ────────────────────────────────────────────────────────────────────

class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID]       = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    firebase_uid: Mapped[str]   = mapped_column(String(128), unique=True, nullable=False, index=True)
    phone: Mapped[str]          = mapped_column(String(20), unique=True, nullable=False)
    display_name: Mapped[str]   = mapped_column(String(64), nullable=False)
    avatar_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    avg_rating: Mapped[float]   = mapped_column(Float, default=0.0, server_default="0.0")
    rating_count: Mapped[int]   = mapped_column(Integer, default=0, server_default="0")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, server_default=func.now())

    trips_as_driver: Mapped[list["Trip"]] = relationship(back_populates="driver", cascade="all, delete-orphan")
    participations: Mapped[list["TripPassenger"]] = relationship(back_populates="user", cascade="all, delete-orphan")
    messages: Mapped[list["Message"]] = relationship(back_populates="sender")
    declarations: Mapped[list["Declaration"]] = relationship(back_populates="user")
    ratings_given: Mapped[list["Rating"]] = relationship(foreign_keys="Rating.rater_id", back_populates="rater")
    ratings_received: Mapped[list["Rating"]] = relationship(foreign_keys="Rating.rated_id", back_populates="rated")


# ── Trips ────────────────────────────────────────────────────────────────────

class Trip(Base):
    __tablename__ = "trips"

    id: Mapped[uuid.UUID]        = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    driver_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    departure_city: Mapped[str]  = mapped_column(String(128), nullable=False)
    departure_lat: Mapped[float] = mapped_column(Float, nullable=False)
    departure_lng: Mapped[float] = mapped_column(Float, nullable=False)
    depart_at: Mapped[datetime]  = mapped_column(DateTime(timezone=True), nullable=False)
    return_at: Mapped[datetime]  = mapped_column(DateTime(timezone=True), nullable=False)
    seats_total: Mapped[int]     = mapped_column(Integer, nullable=False)
    seats_available: Mapped[int] = mapped_column(Integer, nullable=False)
    notes: Mapped[str | None]    = mapped_column(Text, nullable=True)
    # status: open | full | completed | cancelled
    status: Mapped[str]          = mapped_column(String(16), default="open", server_default="open", nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, server_default=func.now())

    driver: Mapped["User"] = relationship(back_populates="trips_as_driver")
    passengers: Mapped[list["TripPassenger"]] = relationship(back_populates="trip", cascade="all, delete-orphan")
    messages: Mapped[list["Message"]] = relationship(back_populates="trip", cascade="all, delete-orphan")
    declarations: Mapped[list["Declaration"]] = relationship(back_populates="trip", cascade="all, delete-orphan")
    ratings: Mapped[list["Rating"]] = relationship(back_populates="trip")


# ── Trip passengers ──────────────────────────────────────────────────────────

class TripPassenger(Base):
    __tablename__ = "trip_passengers"
    __table_args__ = (UniqueConstraint("trip_id", "user_id"),)

    id: Mapped[uuid.UUID]        = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    trip_id: Mapped[uuid.UUID]   = mapped_column(ForeignKey("trips.id", ondelete="CASCADE"), nullable=False)
    user_id: Mapped[uuid.UUID]   = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    # status: pending | accepted | rejected
    status: Mapped[str]          = mapped_column(String(16), default="pending", server_default="pending", nullable=False)
    intro_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    joined_at: Mapped[datetime]  = mapped_column(DateTime(timezone=True), default=_now, server_default=func.now())

    trip: Mapped["Trip"] = relationship(back_populates="passengers")
    user: Mapped["User"] = relationship(back_populates="participations")


# ── Declarations (voluntary "I'm taking…") ──────────────────────────────────

class Declaration(Base):
    __tablename__ = "declarations"
    __table_args__ = (UniqueConstraint("trip_id", "user_id", "item_type"),)

    id: Mapped[uuid.UUID]        = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    trip_id: Mapped[uuid.UUID]   = mapped_column(ForeignKey("trips.id", ondelete="CASCADE"), nullable=False)
    user_id: Mapped[uuid.UUID]   = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    item_type: Mapped[str]       = mapped_column(String(64), nullable=False)
    quantity: Mapped[float]      = mapped_column(Float, nullable=False, default=0)

    trip: Mapped["Trip"] = relationship(back_populates="declarations")
    user: Mapped["User"] = relationship(back_populates="declarations")


# ── Messages (72h auto-wiped via pg_cron) ───────────────────────────────────

class Message(Base):
    __tablename__ = "messages"

    id: Mapped[uuid.UUID]        = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    trip_id: Mapped[uuid.UUID]   = mapped_column(ForeignKey("trips.id", ondelete="CASCADE"), nullable=False)
    sender_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    content: Mapped[str]         = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, server_default=func.now(), index=True)

    trip: Mapped["Trip"] = relationship(back_populates="messages")
    sender: Mapped["User"] = relationship(back_populates="messages")


# ── Ratings ──────────────────────────────────────────────────────────────────

class Rating(Base):
    __tablename__ = "ratings"
    __table_args__ = (UniqueConstraint("rater_id", "rated_id", "trip_id"),)

    id: Mapped[uuid.UUID]        = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    rater_id: Mapped[uuid.UUID]  = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    rated_id: Mapped[uuid.UUID]  = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    trip_id: Mapped[uuid.UUID]   = mapped_column(ForeignKey("trips.id", ondelete="SET NULL"), nullable=True)
    score: Mapped[int]           = mapped_column(Integer, CheckConstraint("score BETWEEN 1 AND 5"), nullable=False)
    comment: Mapped[str | None]  = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, server_default=func.now())

    rater: Mapped["User"] = relationship(foreign_keys=[rater_id], back_populates="ratings_given")
    rated: Mapped["User"] = relationship(foreign_keys=[rated_id], back_populates="ratings_received")
    trip: Mapped["Trip"]  = relationship(back_populates="ratings")


# ── Allowances (scraped from DGDDI) ─────────────────────────────────────────

class AllowanceItem(Base):
    __tablename__ = "allowance_items"

    id: Mapped[int]              = mapped_column(Integer, primary_key=True, autoincrement=True)
    item_type: Mapped[str]       = mapped_column(String(64), unique=True, nullable=False)
    label: Mapped[str]           = mapped_column(String(128), nullable=False)
    unit: Mapped[str]            = mapped_column(String(32), nullable=False)
    per_adult: Mapped[float]     = mapped_column(Float, nullable=False)
    per_minor: Mapped[float | None] = mapped_column(Float, nullable=True)   # None = forbidden
    per_child: Mapped[float | None] = mapped_column(Float, nullable=True)   # None = forbidden
    last_updated: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)
