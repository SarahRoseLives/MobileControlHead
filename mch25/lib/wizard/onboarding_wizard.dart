import 'package:flutter/material.dart';

import 'slides.dart';

class OnboardingWizard extends StatefulWidget {
  final VoidCallback onSkip;
  final VoidCallback onDone;
  const OnboardingWizard({required this.onSkip, required this.onDone, Key? key}) : super(key: key);

  @override
  State<OnboardingWizard> createState() => _OnboardingWizardState();
}

class _OnboardingWizardState extends State<OnboardingWizard> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  void _goToPage(int index) {
    _controller.animateToPage(index, duration: Duration(milliseconds: 350), curve: Curves.ease);
  }

  @override
  Widget build(BuildContext context) {
    final slides = onboardingSlides;
    return Scaffold(
      backgroundColor: Color(0xFF181818),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  flex: 7,
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: slides.length,
                    onPageChanged: (idx) => setState(() => _currentPage = idx),
                    itemBuilder: (context, idx) => slides[idx],
                  ),
                ),
                // Dots
                Padding(
                  padding: const EdgeInsets.only(top: 0, bottom: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      slides.length,
                      (idx) => Container(
                        margin: EdgeInsets.symmetric(horizontal: 4),
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _currentPage == idx ? Colors.white : Colors.white38,
                        ),
                      ),
                    ),
                  ),
                ),
                // Navigation Buttons
                Padding(
                  padding: const EdgeInsets.only(bottom: 36),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_currentPage > 0)
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white24,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => _goToPage(_currentPage - 1),
                          child: Text("Back"),
                        ),
                      if (_currentPage > 0) SizedBox(width: 20),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: () {
                          if (_currentPage == slides.length - 1) {
                            widget.onDone();
                          } else {
                            _goToPage(_currentPage + 1);
                          }
                        },
                        child: Text(_currentPage == slides.length - 1 ? "Done" : "Next"),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Skip button (top right)
            Positioned(
              top: 12,
              right: 16,
              child: TextButton(
                onPressed: widget.onSkip,
                child: Text("SKIP", style: TextStyle(color: Colors.white70, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}