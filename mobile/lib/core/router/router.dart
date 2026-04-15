import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/login_screen.dart';
import '../../features/trips/trip_list_screen.dart';
import '../../features/trips/trip_detail_screen.dart';
import '../../features/trips/trip_create_screen.dart';
import '../../features/calculator/calculator_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/chat/chat_screen.dart';

// Listens to Firebase auth state so the router reacts to sign-in/sign-out.
final _authStateNotifier = ValueNotifier<bool>(false);

void initAuthNotifier() {
  FirebaseAuth.instance.authStateChanges().listen((user) {
    _authStateNotifier.value = user != null;
  });
}

final router = GoRouter(
  initialLocation: '/home',
  refreshListenable: _authStateNotifier,
  redirect: (context, state) {
    final authed = FirebaseAuth.instance.currentUser != null;
    final onLogin = state.matchedLocation == '/login';
    if (!authed && !onLogin) return '/login';
    if (authed && onLogin) return '/home';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
    GoRoute(
      path: '/home',
      builder: (_, _) => const TripListScreen(),
      routes: [
        GoRoute(path: 'create', builder: (_, _) => const TripCreateScreen()),
      ],
    ),
    GoRoute(
      path: '/trip/:id',
      builder: (_, state) => TripDetailScreen(tripId: state.pathParameters['id']!),
      routes: [
        GoRoute(
          path: 'chat',
          builder: (_, state) => ChatScreen(tripId: state.pathParameters['id']!),
        ),
      ],
    ),
    GoRoute(
      path: '/profile/:id',
      builder: (_, state) => ProfileScreen(userId: state.pathParameters['id']!),
    ),
    GoRoute(path: '/calculator', builder: (_, _) => const CalculatorScreen()),
  ],
);
