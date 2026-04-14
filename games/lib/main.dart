import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const FlappyBirdApp());
}

class FlappyBirdApp extends StatelessWidget {
  const FlappyBirdApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flappy Bird',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'monospace'),
      home: const GameScreen(),
    );
  }
}


const double kGravity = 0.5;
const double kFlapStrength = -10.0;
const double kPipeWidth = 70.0;
const double kPipeGap = 170.0;
const double kPipeSpeed = 3.5;
const double kBirdSize = 60;
const double kGroundHeight = 90.0;
const double kPipeSpawnInterval = 2.2; // seconds


// DATA MODELS

class Pipe {
  double x;
  final double topHeight;
  bool scored;

  Pipe({required this.x, required this.topHeight, this.scored = false});

  double get bottomTop => topHeight + kPipeGap;
}

class Particle {
  double x, y, vx, vy, size, opacity;
  Color color;

  Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.opacity,
    required this.color,
  });
}

enum GameState { idle, playing, dying, dead }


// GAME SCREEN

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ticker;


  double birdY = 0;
  double birdVelocity = 0;
  double birdRotation = 0;
  double _wingAngle = 0;
  double _wingDir = 1;


  GameState gameState = GameState.idle;
  List<Pipe> pipes = [];
  int score = 0;
  int bestScore = 0;
  double _pipeTimer = 0;
  double _deathTimer = 0;
  final Random _rng = Random();

  // Parallax clouds & stars
  List<_Cloud> clouds = [];
  List<_Star> stars = [];

  
  List<Particle> particles = [];

  // Screen
  double screenW = 0;
  double screenH = 0;

  // Flash on hit
  double _flashOpacity = 0;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(days: 999),
    )..addListener(_tick);
    _ticker.forward();

    for (int i = 0; i < 6; i++) clouds.add(_Cloud.random(_rng, 400, i * 70.0));
    for (int i = 0; i < 60; i++) stars.add(_Star.random(_rng));
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final dt = 1 / 60.0;

    setState(() {
      // Wing flap animation
      _wingAngle += _wingDir * 0.15;
      if (_wingAngle.abs() > 0.4) _wingDir *= -1;

      // Cloud parallax
      for (var c in clouds) {
        c.x -= c.speed;
        if (c.x < -c.width) c.x = screenW + c.width;
      }

      // Particles
      particles.removeWhere((p) => p.opacity <= 0);
      for (var p in particles) {
        p.x += p.vx;
        p.y += p.vy;
        p.vy += 0.15;
        p.opacity -= 0.025;
        p.size *= 0.97;
      }

      // Flash fade
      if (_flashOpacity > 0) _flashOpacity -= 0.08;

      if (gameState == GameState.playing) {
        // Physics
        birdVelocity += kGravity;
        birdY += birdVelocity;

        // Rotation
        birdRotation = (birdVelocity / 15.0).clamp(-0.5, 1.2);

        // Pipe movement & spawning
        _pipeTimer += dt;
        if (_pipeTimer >= kPipeSpawnInterval) {
          _pipeTimer = 0;
          final topH =
              80 +
              _rng.nextDouble() * (screenH - kGroundHeight - kPipeGap - 160);
          pipes.add(Pipe(x: screenW + kPipeWidth, topHeight: topH));
        }

        for (var pipe in pipes) {
          pipe.x -= kPipeSpeed;
        }
        pipes.removeWhere((p) => p.x < -kPipeWidth * 2);

        // Scoring
        final birdCenterX = screenW * 0.35;
        for (var pipe in pipes) {
          if (!pipe.scored && pipe.x + kPipeWidth < birdCenterX) {
            pipe.scored = true;
            score++;
            _spawnScoreParticles();
            HapticFeedback.lightImpact();
          }
        }

        // Collision
        _checkCollision();
      } else if (gameState == GameState.dying) {
        _deathTimer += dt;
        birdVelocity += kGravity * 1.5;
        birdY += birdVelocity;
        birdRotation = 1.5;
        if (_deathTimer > 1.2) gameState = GameState.dead;
      }
    });
  }

  void _checkCollision() {
    final birdCX = screenW * 0.35;
    final birdCY = birdY + screenH / 2;
    final birdR = kBirdSize * 0.38;

    // Ground
    if (birdCY + birdR >= screenH - kGroundHeight) {
      _die();
      return;
    }
    // Ceiling
    if (birdCY - birdR <= 0) {
      _die();
      return;
    }

    // Pipes (circle vs rect)
    for (var pipe in pipes) {
      final pLeft = pipe.x;
      final pRight = pipe.x + kPipeWidth;
      final topBottom = pipe.topHeight;
      final bottomTop = pipe.bottomTop;

      // AABB + circle
      if (birdCX + birdR > pLeft && birdCX - birdR < pRight) {
        if (birdCY - birdR < topBottom || birdCY + birdR > bottomTop) {
          _die();
          return;
        }
      }
    }
  }

  void _die() {
    if (gameState != GameState.playing) return;
    gameState = GameState.dying;
    _deathTimer = 0;
    _flashOpacity = 1.0;
    if (score > bestScore) bestScore = score;
    _spawnDeathParticles();
    HapticFeedback.heavyImpact();
  }

  void _flap() {
    if (gameState == GameState.idle) {
      _startGame();
      return;
    }
    if (gameState != GameState.playing) return;
    birdVelocity = kFlapStrength;
    _spawnFlapParticles();
    HapticFeedback.selectionClick();
  }

  void _startGame() {
    setState(() {
      birdY = 0;
      birdVelocity = 0;
      birdRotation = 0;
      score = 0;
      pipes.clear();
      _pipeTimer = kPipeSpawnInterval * 0.6;
      particles.clear();
      gameState = GameState.playing;
      birdVelocity = kFlapStrength;
    });
  }

  void _restart() {
    setState(() {
      gameState = GameState.idle;
    });
  }

  void _spawnScoreParticles() {
    final bx = screenW * 0.35;
    final by = birdY + screenH / 2;
    for (int i = 0; i < 12; i++) {
      final angle = _rng.nextDouble() * pi * 2;
      final speed = 2 + _rng.nextDouble() * 4;
      particles.add(
        Particle(
          x: bx,
          y: by,
          vx: cos(angle) * speed,
          vy: sin(angle) * speed,
          size: 5 + _rng.nextDouble() * 5,
          opacity: 1.0,
          color: [
            const Color(0xFFFFD700),
            const Color(0xFFFFEB3B),
            const Color(0xFFFF9800),
          ][_rng.nextInt(3)],
        ),
      );
    }
  }

  void _spawnFlapParticles() {
    final bx = screenW * 0.35;
    final by = birdY + screenH / 2;
    for (int i = 0; i < 5; i++) {
      particles.add(
        Particle(
          x: bx - 10,
          y: by + 10,
          vx: -1 - _rng.nextDouble() * 2,
          vy: 1 + _rng.nextDouble() * 2,
          size: 4 + _rng.nextDouble() * 4,
          opacity: 0.7,
          color: Colors.white.withOpacity(0.8),
        ),
      );
    }
  }

  void _spawnDeathParticles() {
    final bx = screenW * 0.35;
    final by = birdY + screenH / 2;
    for (int i = 0; i < 25; i++) {
      final angle = _rng.nextDouble() * pi * 2;
      final speed = 2 + _rng.nextDouble() * 6;
      particles.add(
        Particle(
          x: bx,
          y: by,
          vx: cos(angle) * speed,
          vy: sin(angle) * speed,
          size: 6 + _rng.nextDouble() * 8,
          opacity: 1.0,
          color: [
            const Color(0xFFFF5252),
            const Color(0xFFFF9800),
            const Color(0xFFFFD700),
            Colors.white,
          ][_rng.nextInt(4)],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        screenW = constraints.maxWidth;
        screenH = constraints.maxHeight;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTapDown: (_) => _flap(),
            child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              children: [
                // ── Sky gradient
                _buildSky(),

                // ── Stars (night twinkling)
                CustomPaint(
                  size: Size(screenW, screenH),
                  painter: _StarPainter(stars: stars),
                ),

                // ── Clouds
                ...clouds.map((c) => _buildCloud(c)),

                // ── Pipes
                ...pipes.map((p) => _buildPipe(p)),

                // ── Ground
                _buildGround(),

                // ── Particles
                CustomPaint(
                  size: Size(screenW, screenH),
                  painter: _ParticlePainter(particles: particles),
                ),

                // ── Bird
                _buildBird(),

                // ── Score HUD
                if (gameState == GameState.playing ||
                    gameState == GameState.dying)
                  _buildScoreHUD(),

                // ── Flash overlay
                if (_flashOpacity > 0)
                  Opacity(
                    opacity: _flashOpacity.clamp(0.0, 1.0),
                    child: Container(color: Colors.white),
                  ),

                // ── Idle screen
                if (gameState == GameState.idle) _buildIdleScreen(),

                // ── Dead screen
                if (gameState == GameState.dead) _buildDeadScreen(),
              ],
            ),
          ),
          ),
        );
      },
    );
  }

  

  Widget _buildSky() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0A0020),
            Color(0xFF1A0050),
            Color(0xFF2D1B69),
            Color(0xFF5B2A8C),
            Color(0xFFFF6B6B),
            Color(0xFFFFD166),
          ],
          stops: [0.0, 0.2, 0.45, 0.65, 0.85, 1.0],
        ),
      ),
    );
  }

  Widget _buildCloud(_Cloud c) {
    return Positioned(
      left: c.x,
      top: c.y,
      child: Opacity(
        opacity: c.opacity,
        child: Container(
          width: c.width,
          height: c.height,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(c.height / 2),
            boxShadow: [
              BoxShadow(
                color: Colors.purple.withOpacity(0.1),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPipe(Pipe pipe) {
    return Stack(
      children: [
        // Top pipe
        Positioned(
          left: pipe.x,
          top: 0,
          child: _PipeWidget(
            width: kPipeWidth,
            height: pipe.topHeight,
            isTop: true,
          ),
        ),
        // Bottom pipe
        Positioned(
          left: pipe.x,
          top: pipe.bottomTop,
          child: _PipeWidget(
            width: kPipeWidth,
            height: screenH - pipe.bottomTop,
            isTop: false,
          ),
        ),
      ],
    );
  }

  Widget _buildGround() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        height: kGroundHeight,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF4CAF50), Color(0xFF388E3C), Color(0xFF2E7D32)],
          ),
        ),
        child: Column(
          children: [
            Container(
              height: 14,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [const Color(0xFF66BB6A), const Color(0xFF4CAF50)],
                ),
              ),
            ),
            // Dirt stripes
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF8D6E63), Color(0xFF6D4C41)],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBird() {
    final by = birdY + screenH / 2;
    return Positioned(
      left: screenW * 0.35 - kBirdSize / 2,
      top: by - kBirdSize / 2,
      child: Transform.rotate(
        angle: birdRotation,
        child: Image.asset(
          'assets/bird.png', 
          width: kBirdSize,
          height: kBirdSize,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _buildScoreHUD() {
    return Positioned(
      top: 60,
      left: 0,
      right: 0,
      child: Center(
        child: Column(
          children: [
            Text(
              '$score',
              style: const TextStyle(
                fontSize: 72,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1,
                shadows: [
                  Shadow(
                    offset: Offset(3, 3),
                    blurRadius: 0,
                    color: Color(0xFF000000),
                  ),
                  Shadow(
                    offset: Offset(0, 0),
                    blurRadius: 20,
                    color: Color(0xFFFFD700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdleScreen() {
    return Container(
      color: Colors.black.withOpacity(0.5),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo text
            const Text(
              'FLAPPY',
              style: TextStyle(
                fontSize: 54,
                fontWeight: FontWeight.w900,
                color: Color(0xFFFFD700),
                letterSpacing: 8,
                shadows: [
                  Shadow(
                    offset: Offset(4, 4),
                    blurRadius: 0,
                    color: Color(0xFF8B6914),
                  ),
                  Shadow(
                    offset: Offset(0, 0),
                    blurRadius: 30,
                    color: Color(0xFFFFD700),
                  ),
                ],
              ),
            ),
            const Text(
              'BIRD',
              style: TextStyle(
                fontSize: 72,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 10,
                height: 0.9,
                shadows: [
                  Shadow(
                    offset: Offset(4, 4),
                    blurRadius: 0,
                    color: Color(0xFF333333),
                  ),
                  Shadow(
                    offset: Offset(0, 0),
                    blurRadius: 30,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 60),
        
            Image.asset(
              'assets/bird.png',
              width: 80,
              height: 80,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 50),
            _TapButton(label: 'TAP TO START', onTap: _flap),
            if (bestScore > 0) ...[
              const SizedBox(height: 20),
              Text(
                'BEST: $bestScore',
                style: const TextStyle(
                  fontSize: 20,
                  color: Color(0xFFFFD700),
                  letterSpacing: 4,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDeadScreen() {
    return Container(
      color: Colors.black.withOpacity(0.6),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'GAME OVER',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w900,
                color: Color(0xFFFF5252),
                letterSpacing: 4,
                shadows: [
                  Shadow(
                    offset: Offset(3, 3),
                    blurRadius: 0,
                    color: Color(0xFF8B0000),
                  ),
                  Shadow(
                    offset: Offset(0, 0),
                    blurRadius: 25,
                    color: Color(0xFFFF5252),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            _ScorePanel(score: score, best: bestScore),
            const SizedBox(height: 40),
            _TapButton(label: 'PLAY AGAIN', onTap: _restart),
          ],
        ),
      ),
    );
  }
}


class _PipeWidget extends StatelessWidget {
  final double width, height;
  final bool isTop;

  const _PipeWidget({
    required this.width,
    required this.height,
    required this.isTop,
  });

  @override
  Widget build(BuildContext context) {
    const capH = 28.0;
    final capColor1 = const Color(0xFF66BB6A);
    final capColor2 = const Color(0xFF388E3C);
    final bodyColor1 = const Color(0xFF4CAF50);
    final bodyColor2 = const Color(0xFF2E7D32);

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
   
          Positioned(
            left: 6,
            right: 6,
            top: isTop ? 0 : capH,
            bottom: isTop ? capH : 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF81C784),
                    bodyColor1,
                    bodyColor2,
                    const Color(0xFF1B5E20),
                  ],
                  stops: const [0.0, 0.3, 0.7, 1.0],
                ),
              ),
            ),
          ),
          // Cap
          Positioned(
            left: 0,
            right: 0,
            top: isTop ? height - capH : 0,
            child: Container(
              height: capH,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF81C784),
                    capColor1,
                    capColor2,
                    const Color(0xFF1B5E20),
                  ],
                  stops: const [0.0, 0.3, 0.7, 1.0],
                ),
                borderRadius: isTop
                    ? const BorderRadius.only(
                        bottomLeft: Radius.circular(5),
                        bottomRight: Radius.circular(5),
                      )
                    : const BorderRadius.only(
                        topLeft: Radius.circular(5),
                        topRight: Radius.circular(5),
                      ),
              ),
            ),
          ),
          // Shine
          Positioned(
            left: 10,
            top: isTop ? 0 : capH + 2,
            bottom: isTop ? capH + 2 : 0,
            width: 6,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white.withOpacity(0.4), Colors.transparent],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
class _ParticlePainter extends CustomPainter {
  final List<Particle> particles;
  const _ParticlePainter({required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    for (var p in particles) {
      canvas.drawCircle(
        Offset(p.x, p.y),
        p.size,
        Paint()..color = p.color.withOpacity(p.opacity.clamp(0.0, 1.0)),
      );
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => true;
}

class _StarPainter extends CustomPainter {
  final List<_Star> stars;
  const _StarPainter({required this.stars});

  @override
  void paint(Canvas canvas, Size size) {
    for (var s in stars) {
      final opacity =
          0.4 +
          0.6 * sin(DateTime.now().millisecondsSinceEpoch / 1000.0 + s.phase);
      canvas.drawCircle(
        Offset(s.x * size.width, s.y * size.height),
        s.radius,
        Paint()..color = Colors.white.withOpacity(opacity.clamp(0.1, 1.0)),
      );
    }
  }

  @override
  bool shouldRepaint(_StarPainter _) => true;
}


class _ScorePanel extends StatelessWidget {
  final int score, best;
  const _ScorePanel({required this.score, required this.best});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFFFD700).withOpacity(0.5),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD700).withOpacity(0.15),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ScoreStat(label: 'SCORE', value: '$score'),
          Container(width: 1, height: 50, color: Colors.white24),
          _ScoreStat(
            label: 'BEST',
            value: '$best',
            highlight: score >= best && score > 0,
          ),
        ],
      ),
    );
  }
}

class _ScoreStat extends StatelessWidget {
  final String label, value;
  final bool highlight;
  const _ScoreStat({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 13,
            letterSpacing: 3,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 42,
            fontWeight: FontWeight.w900,
            color: highlight ? const Color(0xFFFFD700) : Colors.white,
            shadows: highlight
                ? const [
                    Shadow(
                      offset: Offset(0, 0),
                      blurRadius: 20,
                      color: Color(0xFFFFD700),
                    ),
                  ]
                : const [],
          ),
        ),
        if (highlight)
          const Text(
            '★ NEW BEST',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFFFFD700),
              letterSpacing: 2,
              fontWeight: FontWeight.bold,
            ),
          ),
      ],
    );
  }
}

class _TapButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _TapButton({required this.label, required this.onTap});

  @override
  State<_TapButton> createState() => _TapButtonState();
}

class _TapButtonState extends State<_TapButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween(
      begin: 1.0,
      end: 1.06,
    ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFD700), Color(0xFFFF9800)],
            ),
            borderRadius: BorderRadius.circular(50),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFD700).withOpacity(0.5),
                blurRadius: 20,
                spreadRadius: 2,
              ),
              const BoxShadow(
                color: Color(0xFF000000),
                offset: Offset(0, 5),
                blurRadius: 10,
              ),
            ],
          ),
          child: Text(
            widget.label,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Colors.black,
              letterSpacing: 3,
            ),
          ),
        ),
      ),
    );
  }
}


class _Cloud {
  double x, y, width, height, speed, opacity;

  _Cloud({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.speed,
    required this.opacity,
  });

  factory _Cloud.random(Random rng, double screenW, double yBase) {
    return _Cloud(
      x: rng.nextDouble() * screenW,
      y: yBase + rng.nextDouble() * 40,
      width: 80 + rng.nextDouble() * 120,
      height: 30 + rng.nextDouble() * 30,
      speed: 0.3 + rng.nextDouble() * 0.4,
      opacity: 0.08 + rng.nextDouble() * 0.12,
    );
  }
}

class _Star {
  final double x, y, radius, phase;
  _Star({
    required this.x,
    required this.y,
    required this.radius,
    required this.phase,
  });

  factory _Star.random(Random rng) {
    return _Star(
      x: rng.nextDouble(),
      y: rng.nextDouble() * 0.65,
      radius: 0.5 + rng.nextDouble() * 1.5,
      phase: rng.nextDouble() * pi * 2,
    );
  }
}
