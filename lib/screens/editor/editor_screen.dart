import 'package:flutter/material.dart';
import 'dart:io';
import 'package:video_player/video_player.dart';

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:path_provider/path_provider.dart';




class EditorScreen extends StatefulWidget {
  final List<File> mediaFiles;

  const EditorScreen({
    super.key,
    required this.mediaFiles,
  });

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  int selectedTool = 0;
  int selectedClip = 0;

  VideoPlayerController? _videoController;
  bool _videoReady = false;
  bool _isDraggingTimeline = false;
  double _timelineValue = 0;
  double trimStartMs = 0;
  double trimEndMs = 0;



  bool showRatios = false;
  String selectedRatio = 'Original';
  String? _videoError;

  String _formatDuration(Duration duration) {
    final minutes =
    duration.inMinutes.remainder(60).toString().padLeft(2, '0');

    final seconds =
    duration.inSeconds.remainder(60).toString().padLeft(2, '0');

    return '$minutes:$seconds';
  }


  @override
  void initState() {
    super.initState();

    if (widget.mediaFiles.isNotEmpty) {
      _loadVideo(0);
    }
  }

  Future<void> _loadVideo(int index) async {
    if (index < 0 || index >= widget.mediaFiles.length) {
      return;
    }

    setState(() {
      _videoReady = false;
      _videoError = null;
    });

    await _videoController?.dispose();

    try {
      final file = widget.mediaFiles[index];

      if (!await file.exists()) {
        throw Exception('Video file not found');
      }

      final controller = VideoPlayerController.file(file);
      _videoController = controller;

      await controller.initialize();

      trimStartMs = 0;
      trimEndMs =
          controller.value.duration.inMilliseconds.toDouble();

      controller.addListener(() {
        if (!mounted || _isDraggingTimeline) return;

        setState(() {
          _timelineValue =
              controller.value.position.inMilliseconds.toDouble();
        });
      });

      if (!mounted) return;

      setState(() {
        selectedClip = index;
        _videoReady = true;
        _videoError = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _videoReady = false;
        _videoError = e.toString();
      });
    }
  }


  Widget _dropdownRatio(String ratio) {
    final selected = selectedRatio == ratio;

    return InkWell(
      onTap: () {
        setState(() {
          selectedRatio = ratio;
          showRatios = false;
        });
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 11,
        ),
        color: selected
            ? const Color(0xFF24121C)
            : Colors.transparent,
        child: Row(
          children: [
            Icon(
              ratio == '9:16'
                  ? Icons.smartphone_rounded
                  : ratio == '16:9'
                  ? Icons.tv_rounded
                  : ratio == '1:1'
                  ? Icons.crop_square_rounded
                  : Icons.crop_rounded,
              color: selected
                  ? const Color(0xFFFF2D75)
                  : Colors.white60,
              size: 18,
            ),

            const SizedBox(width: 10),

            Text(
              ratio,
              style: TextStyle(
                color: selected
                    ? Colors.white
                    : Colors.white70,
                fontSize: 13,
                fontWeight: selected
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),

            const Spacer(),

            if (selected)
              const Icon(
                Icons.check_rounded,
                color: Color(0xFFFF2D75),
                size: 18,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _trimVideo({
    required int startMs,
    required int endMs,
  }) async {
    final controller = _videoController;

    if (controller == null || widget.mediaFiles.isEmpty) {
      return;
    }

    final inputFile = widget.mediaFiles[selectedClip];

    if (!await inputFile.exists()) {
      return;
    }

    final outputPath =
        '${Directory.systemTemp.path}/videomitra_trimmed_${DateTime.now().millisecondsSinceEpoch}.mp4';

    final startSeconds = startMs / 1000;
    final durationSeconds = (endMs - startMs) / 1000;

    if (durationSeconds <= 0) {
      return;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return const AlertDialog(
          backgroundColor: Color(0xFF181820),
          content: Row(
            children: [
              CircularProgressIndicator(
                color: Color(0xFFFF2D75),
              ),
              SizedBox(width: 20),
              Expanded(
                child: Text(
                  'Video trim ho raha hai...',
                  style: TextStyle(
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    final command =
        '-y '
        '-ss $startSeconds '
        '-i "${inputFile.path}" '
        '-t $durationSeconds '
        '-map 0 '
        '-c copy '
        '-avoid_negative_ts make_zero '
        '"$outputPath"';
    final session =
    await FFmpegKit.execute(command);

    final returnCode =
    await session.getReturnCode();

    if (!mounted) return;

    Navigator.pop(context);

    if (ReturnCode.isSuccess(returnCode)) {
      await _videoController?.dispose();

      final trimmedFile = File(outputPath);

      final newController =
      VideoPlayerController.file(trimmedFile);

      await newController.initialize();

      if (!mounted) return;

      setState(() {
        _videoController = newController;
        _videoReady = true;
        _videoError = null;
        _timelineValue = 0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Video successfully trimmed'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Video trim failed'),
        ),
      );
    }
  }




  void _showRatioPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF101016),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (context) {
        final ratios = [
          {
            'name': 'Original',
            'ratio': null,
            'icon': Icons.fit_screen_rounded,
          },
          {
            'name': '9:16',
            'ratio': 9 / 16,
            'icon': Icons.smartphone_rounded,
          },
          {
            'name': '16:9',
            'ratio': 16 / 9,
            'icon': Icons.tv_rounded,
          },
          {
            'name': '1:1',
            'ratio': 1.0,
            'icon': Icons.crop_square_rounded,
          },
          {
            'name': '4:5',
            'ratio': 4 / 5,
            'icon': Icons.crop_portrait_rounded,
          },
          {
            'name': '4:3',
            'ratio': 4 / 3,
            'icon': Icons.crop_landscape_rounded,
          },
        ];

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Canvas Ratio',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 18),

                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: ratios.length,
                  gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1,
                  ),
                  itemBuilder: (context, index) {
                    final item = ratios[index];

                    final name = item['name'] as String;

                    final isSelected =
                        selectedRatio == name;

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          selectedRatio = name;
                        });

                        Navigator.pop(context);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF24121C)
                              : const Color(0xFF181820),
                          borderRadius:
                          BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFFFF2D75)
                                : Colors.white10,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment:
                          MainAxisAlignment.center,
                          children: [
                            Icon(
                              item['icon'] as IconData,
                              color: isSelected
                                  ? const Color(0xFFFF2D75)
                                  : Colors.white70,
                              size: 28,
                            ),

                            const SizedBox(height: 8),

                            Text(
                              name,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white60,
                                fontWeight:
                                FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }
  Widget _ratioButton(String ratio) {
    final selected = selectedRatio == ratio;

    return GestureDetector(
      onTap: () {
        setState(() {
          selectedRatio = ratio;
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: 3,
          vertical: 8,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 9,
        ),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFFF2D75)
              : const Color(0xFF181820),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          ratio,
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: selected
                ? FontWeight.bold
                : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  final List<Map<String, dynamic>> tools = [
    {'icon': Icons.content_cut_rounded, 'name': 'Trim'},
    {'icon': Icons.call_split_rounded, 'name': 'Split'},
    {'icon': Icons.delete_outline_rounded, 'name': 'Delete'},
    {'icon': Icons.music_note_rounded, 'name': 'Audio'},
    {'icon': Icons.text_fields_rounded, 'name': 'Text'},
    {'icon': Icons.auto_awesome_rounded, 'name': 'Effects'},
    {'icon': Icons.filter_rounded, 'name': 'Filters'},
    {'icon': Icons.layers_rounded, 'name': 'Overlay'},
    {'icon': Icons.stars_rounded, 'name': 'VFX'},
    {'icon': Icons.tune_rounded, 'name': 'Adjust'},
    {'icon': Icons.emoji_emotions_rounded, 'name': 'Sticker'},
  ];

  void _showTrimPanel() {
    final controller = _videoController;

    if (controller == null || !_videoReady) {
      return;
    }

    final duration = controller.value.duration;

    if (duration <= Duration.zero) {
      return;
    }

    double startMs = 0;
    double endMs = duration.inMilliseconds.toDouble();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF101016),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, modalSetState) {
            final selectedDuration =
            Duration(
              milliseconds:
              (endMs - startMs).round(),
            );

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  18,
                  12,
                  18,
                  18,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius:
                        BorderRadius.circular(10),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Title
                    Row(
                      children: [
                        const Icon(
                          Icons.content_cut_rounded,
                          color: Color(0xFFFF2D75),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Trim Video',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    // Time information
                    Row(
                      mainAxisAlignment:
                      MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Start  ${_formatDuration(
                            Duration(
                              milliseconds:
                              startMs.round(),
                            ),
                          )}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          'Selected  ${_formatDuration(
                            selectedDuration,
                          )}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'End  ${_formatDuration(
                            Duration(
                              milliseconds:
                              endMs.round(),
                            ),
                          )}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Trim range
                    RangeSlider(
                      min: 0,
                      max: duration.inMilliseconds
                          .toDouble(),
                      values: RangeValues(
                        startMs,
                        endMs,
                      ),
                      activeColor:
                      const Color(0xFFFF2D75),
                      inactiveColor: Colors.white12,

                      onChanged: (values) {
                        modalSetState(() {
                          startMs = values.start;
                          endMs = values.end;
                        });

                        // Preview selected start
                        controller.seekTo(
                          Duration(
                            milliseconds:
                            values.start.round(),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 10),

                    // Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              modalSetState(() {
                                startMs = 0;
                                endMs = duration
                                    .inMilliseconds
                                    .toDouble();
                              });

                              controller.seekTo(
                                Duration.zero,
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                color: Colors.white24,
                              ),
                            ),
                            child: const Text(
                              'Reset',
                              style: TextStyle(
                                color: Colors.white70,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(width: 12),

                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              // Selection save.
                              // Actual cutting will be
                              // connected with export later.

                              Navigator.pop(context);

                              setState(() {
                                trimStartMs = startMs;
                                trimEndMs = endMs;

                                _timelineValue = startMs;
                              });

                              await controller.seekTo(
                                Duration(
                                  milliseconds: startMs.round(),
                                ),
                              );
                            },
                            style:
                            ElevatedButton.styleFrom(
                              backgroundColor:
                              const Color(0xFFFF2D75),
                              foregroundColor:
                              Colors.white,
                            ),
                            child: const Text(
                              'Apply',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _togglePlay() {
    final controller = _videoController;

    if (controller == null || !_videoReady) {
      return;
    }

    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      // Video खत्म हो चुका है तो शुरुआत से चलाएँ
      if (controller.value.position >=
          controller.value.duration) {
        controller.seekTo(Duration.zero);
      }

      controller.play();
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050508),

      appBar: AppBar(
        backgroundColor: const Color(0xFF08080D),
        elevation: 0,

        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),

        title: const Text(
          'VideoMitra',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 19,
          ),
        ),

        centerTitle: true,

        actions: [
          GestureDetector(
            onTap: () {
              setState(() {
                showRatios = !showRatios;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF181820),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.crop_rounded,
                    color: Colors.white70,
                    size: 19,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Canvas',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Icon(
                    showRatios
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: Colors.white54,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),

          TextButton(
            onPressed: () {},
            child: const Text(
              'Export',
              style: TextStyle(
                color: Color(0xFFFF2D75),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),

      body: Stack(
        children: [
          Column(
          children: [
          // ================= PREVIEW =================

          Expanded(
            flex: 5,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(
                12,
                12,
                12,
                6,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF09090D),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Colors.white10,
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final controller = _videoController;

                  if (!_videoReady || controller == null) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFFF2D75),
                      ),
                    );
                  }

                  final videoWidth =
                      controller.value.size.width;

                  final videoHeight =
                      controller.value.size.height;

                  if (videoWidth <= 0 || videoHeight <= 0) {
                    return const Center(
                      child: Text(
                        'Video preview unavailable',
                        style: TextStyle(
                          color: Colors.white54,
                        ),
                      ),
                    );
                  }

                  final originalRatio =
                      videoWidth / videoHeight;

                  double previewRatio;

                  switch (selectedRatio) {
                    case '9:16':
                      previewRatio = 9 / 16;
                      break;

                    case '16:9':
                      previewRatio = 16 / 9;
                      break;

                    case '1:1':
                      previewRatio = 1.0;
                      break;

                    case '4:5':
                      previewRatio = 4 / 5;
                      break;

                    case '4:3':
                      previewRatio = 4 / 3;
                      break;

                    default:
                      previewRatio = originalRatio;
                  }

                  final maxWidth = constraints.maxWidth - 20;
                  final maxHeight = constraints.maxHeight - 20;

                  double previewWidth;
                  double previewHeight;

                  if (previewRatio > maxWidth / maxHeight) {
                    previewWidth = maxWidth;
                    previewHeight = previewWidth / previewRatio;
                  } else {
                    previewHeight = maxHeight;
                    previewWidth = previewHeight * previewRatio;
                  }

                  return Center(
                    child: SizedBox(
                      width: previewWidth,
                      height: previewHeight,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Video को stretch नहीं करेंगे
                            Center(
                              child: FittedBox(
                                fit: BoxFit.contain,
                                child: SizedBox(
                                  width: controller.value.size.width,
                                  height: controller.value.size.height,
                                  child: VideoPlayer(controller),
                                ),
                              ),
                            ),

                            // Play / Pause
                            Center(
                              child: GestureDetector(
                                onTap: _togglePlay,
                                child: AnimatedOpacity(
                                  duration: const Duration(
                                    milliseconds: 150,
                                  ),
                                  opacity: controller.value.isPlaying
                                      ? 0.0
                                      : 1.0,
                                  child: Container(
                                    width: 64,
                                    height: 64,
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 42,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },


              ),
            ),
          ),

          // ================= TIME BAR =================

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: Row(
              children: [
                Text(
                  _formatDuration(
                    Duration(
                      milliseconds: _timelineValue.toInt(),
                    ),
                  ),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                  ),
                ),

                Expanded(
                  child: Slider(
                    value: _timelineValue.clamp(
                      0.0,
                      _videoController?.value.duration
                          .inMilliseconds
                          .toDouble() ??
                          1.0,
                    ),
                    min: 0,
                    max: (_videoController?.value.duration
                        .inMilliseconds
                        .toDouble() ??
                        1.0)
                        .clamp(1.0, double.infinity),

                    activeColor: const Color(0xFFFF2D75),
                    inactiveColor: Colors.white12,

                    onChangeStart: (value) {
                      _isDraggingTimeline = true;
                    },

                    onChanged: (value) {
                      setState(() {
                        _timelineValue = value;
                      });

                      _videoController?.seekTo(
                        Duration(
                          milliseconds: value.toInt(),
                        ),
                      );
                    },

                    onChangeEnd: (value) {
                      _isDraggingTimeline = false;
                    },
                  ),
                ),

                Text(
                  _formatDuration(
                    _videoController?.value.duration ??
                        Duration.zero,
                  ),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),


          // ================= TIMELINE =================

          Container(
            height: 125,
            padding: const EdgeInsets.all(10),
            color: const Color(0xFF08080D),

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Timeline',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 5),

                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: 850,
                      child: Column(
                        children: [
                          _timelineRow(
                            'VIDEO',
                            const Color(0xFF286BFF),
                          ),
                          const SizedBox(height: 1),
                          _timelineRow(
                            'AUDIO',
                            const Color(0xFF8B3CFF),
                          ),
                          const SizedBox(height: 1),
                          _timelineRow(
                            'TEXT',
                            const Color(0xFFFF9D3D),
                          ),
                          const SizedBox(height: 1),
                          _timelineRow(
                            'VFX',
                            const Color(0xFFFF2D75),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ================= TOOL BAR =================

          SafeArea(
            top: false,
            child: Container(
              height: 90,
              decoration: const BoxDecoration(
                color: Color(0xFF101016),
                border: Border(
                  top: BorderSide(
                    color: Colors.white12,
                  ),
                ),
              ),

              child: ListView.builder(
                scrollDirection: Axis.horizontal,

                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),

                itemCount: tools.length,

                itemBuilder: (context, index) {
                  final tool = tools[index];
                  final selected = selectedTool == index;


                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        selectedTool = index;
                      });

                      if (tool['name'] == 'Canvas') {
                        setState(() {
                          showRatios = !showRatios;
                        });
                      }

                      if (tool['name'] == 'Trim') {
                        _showTrimPanel();
                      }
                    },

                    child: Container(
                      width: 72,

                      margin: const EdgeInsets.symmetric(
                        horizontal: 3,
                      ),

                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF24121C)
                            : Colors.transparent,

                        borderRadius: BorderRadius.circular(12),

                        border: Border.all(
                          color: selected
                              ? const Color(0xFFFF2D75)
                              : Colors.transparent,
                        ),
                      ),

                      child: Column(
                        mainAxisAlignment:
                        MainAxisAlignment.center,

                        children: [
                          Icon(
                            tool['icon'],
                            color: selected
                                ? const Color(0xFFFF2D75)
                                : Colors.white70,
                            size: 25,
                          ),

                          const SizedBox(height: 5),

                          Text(
                            tool['name'],
                            style: TextStyle(
                              color: selected
                                  ? Colors.white
                                  : Colors.white54,
                              fontSize: 11,
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),

          // ================= CANVAS DROPDOWN =================

          if (showRatios)
            Positioned(
              top: 0,
              right: 55,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 155,
                  padding: const EdgeInsets.symmetric(
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF181820),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white12,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 15,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _dropdownRatio('9:16'),
                      _dropdownRatio('16:9'),
                      _dropdownRatio('Original'),
                      _dropdownRatio('1:1'),
                      _dropdownRatio('4:3'),
                    ],
                  ),
                ),
              ),
            ),
    ]
      )
    );
  }

  Widget _timelineRow(
      String label,
      Color color,
      ) {
    return SizedBox(
      height: 20,
      child: Row(
        children: [
          SizedBox(
            width: 55,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          Expanded(
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),

                Positioned(
                  left: 5,
                  right: 120,
                  top: 2,
                  bottom: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}