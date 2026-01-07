import 'package:flutter/material.dart';
import 'onboarding_slide.dart';

final List<Widget> onboardingSlides = [
  OnboardingSlide(
    icon: Icons.radio,
    title: "Welcome to Mobile Control Head 25",
    subtitle: "This wizard will help you get up and running with OP25 and our control head.",
  ),
  OnboardingSlide(
    icon: Icons.settings,
    title: "Step 1: Install UserLand",
    subtitle: "You'll need to install UserLand so that you can install OP25.",
  ),
    OnboardingSlide(
    icon: Icons.settings,
    title: "Step 2: Install OP25",
    subtitle: "You'll need to install OP25 on your device. The app will guide you through the process.",
  ),
  OnboardingSlide(
    icon: Icons.check_circle_outline,
    title: "You're ready!",
    subtitle: "You can access this wizard again from the menu at any time.",
  ),
];