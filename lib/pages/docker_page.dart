import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../dsm/dsm_client.dart';
import '../dsm/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_icon_tile.dart';
import '../widgets/feedback.dart';
import '../widgets/surfaces.dart';
import '../widgets/ui_kit.dart';

class DockerPage extends StatefulWidget {
  const DockerPage({super.key});

  @override
  State<DockerPage> createState() => _DockerPageState();
}

class _DockerPageState extends State<DockerPage> {
  List<DockerContainer> _containers = [];
  List<DockerImage> _images = [];
  bool _loading = true;
  String? _error;
  int _tab = 0;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final service = context.read<AppState>().service;
    if (service == null) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        service.dockerContainers(),
        service.dockerImages(),
      ]);
      if (!mounted) return;
      setState(() {
        _containers = results[0] as List<DockerContainer>;
        _images = results[1] as List<DockerImage>;
        _loading = false;
        _error = null;
      });
    } on DsmException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _action(DockerContainer container, String action) async {
    final service = context.read<AppState>().service!;
    setState(() => _busy.add(container.name));
    try {
      await service.dockerAction(container.name, action);
      if (!mounted) return;
      showToast(context, switch (action) {
        'start' => '${container.name} 已启动',
        'stop' => '${container.name} 已停止',
        'restart' => '${container.name} 已重启',
        'delete' => '${container.name} 已删除',
        _ => '操作完成',
      });
      await _load();
    } on DsmException catch (e) {
      if (mounted) showToast(context, e.message, icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busy.remove(container.name));
    }
  }

  Future<void> _pull() async {
    final state = context.read<AppState>();
    final repository = TextEditingController();
    final tag = TextEditingController(text: 'latest');
    final mirror = TextEditingController(text: state.dockerMirror);
    await showAppSheet(
      context,
      title: '拉取镜像',
      subtitle: '从当前 Docker 仓库拉取镜像',
      children: [
        TextField(controller: repository, decoration: const InputDecoration(hintText: '镜像名称，例如 nginx 或 grafana/grafana')),
        const SizedBox(height: 10),
        TextField(controller: tag, decoration: const InputDecoration(hintText: '标签，默认 latest')),
        const SizedBox(height: 10),
        TextField(
          controller: mirror,
          decoration: const InputDecoration(hintText: '镜像加速站（可选），如 docker.m.daocloud.io'),
        ),
        const SizedBox(height: 4),
        Text('Docker Hub 镜像会自动拼接加速站前缀；带域名的镜像保持原样。', style: context.texts.labelSmall?.copyWith(color: context.colors.textTertiary, fontSize: 10.5)),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () async {
            var repo = repository.text.trim();
            final imageTag = tag.text.trim().isEmpty ? 'latest' : tag.text.trim();
            final prefix = mirror.text.trim().replaceAll(RegExp(r'/+$'), '');
            if (repo.isEmpty) return;
            await state.setDockerMirror(prefix);
            if (prefix.isNotEmpty && !repo.split('/').first.contains('.')) {
              repo = '$prefix/$repo';
            }
            Navigator.pop(context);
            try {
              await context.read<AppState>().service!.dockerPull(repo, imageTag);
              if (mounted) showToast(context, '已开始拉取 $repo:$imageTag');
              await _load();
            } on DsmException catch (e) {
              if (mounted) showToast(context, e.message, icon: Icons.error_outline_rounded);
            }
          },
          child: const Text('开始拉取'),
        ),
      ],
    );
    repository.dispose();
    tag.dispose();
    mirror.dispose();
  }

  Future<DockerImage?> _pickDockerImage() {
    return showModalBottomSheet<DockerImage>(
      context: context,
      backgroundColor: context.colors.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Row(
                children: [
                  Text('选择已有镜像', style: context.texts.titleMedium),
                  const Spacer(),
                  Text('${_images.length} 个', style: context.texts.labelSmall?.copyWith(color: context.colors.textTertiary)),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                itemCount: _images.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final image = _images[index];
                  return ListTile(
                    leading: Icon(Icons.inventory_2_rounded, color: context.colors.primary),
                    title: Text(image.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(formatBytes(image.size), style: context.texts.labelSmall),
                    onTap: () => Navigator.pop(context, image),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _create() async {
    if (_images.isEmpty) {
      showToast(context, '还没有镜像，请先拉取镜像', icon: Icons.info_outline_rounded);
      return;
    }
    final selected = await _pickDockerImage();
    if (selected == null || !mounted) return;
    final name = TextEditingController();
    final hostPort = TextEditingController();
    final containerPort = TextEditingController();
    final hostPath = TextEditingController();
    final containerPath = TextEditingController();
    final env = TextEditingController();
    var autoRestart = true;

    await showAppSheet(
      context,
      title: '创建容器',
      subtitle: '使用 DSM Container Manager 的配置接口',
      children: [
        TextField(controller: name, decoration: const InputDecoration(hintText: '容器名称')),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(color: context.colors.surfaceAlt, borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              Icon(Icons.inventory_2_rounded, size: 18, color: context.colors.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(selected.displayName, style: context.texts.bodyMedium)),
            ],
          ),
        ),
        Row(
          children: [
            Expanded(child: TextField(controller: hostPort, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: '主机端口'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: containerPort, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: '容器端口'))),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: TextField(controller: hostPath, decoration: const InputDecoration(hintText: '主机目录，例如 /volume1/docker/app'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: containerPath, decoration: const InputDecoration(hintText: '容器目录，例如 /data'))),
          ],
        ),
        const SizedBox(height: 10),
        TextField(controller: env, maxLines: 3, minLines: 2, decoration: const InputDecoration(hintText: '环境变量，每行一个 KEY=VALUE（可选）')),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('自动重启', style: context.texts.bodyMedium?.copyWith(color: context.colors.textPrimary, fontSize: 13)),
          value: autoRestart,
          onChanged: (v) => setState(() => autoRestart = v),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () async {
            final containerName = name.text.trim();
            final imageName = selected.displayName;
            if (containerName.isEmpty) {
              showToast(context, '请填写容器名称', icon: Icons.info_outline_rounded);
              return;
            }
            final profile = <String, dynamic>{
              'name': containerName,
              'image': imageName,
              'network': 'bridge',
              'restart': autoRestart ? 'unless-stopped' : 'no',
              'enable_auto_restart': autoRestart,
            };
            if (hostPort.text.trim().isNotEmpty && containerPort.text.trim().isNotEmpty) {
              profile['ports'] = [
                {'host_port': int.tryParse(hostPort.text.trim()) ?? hostPort.text.trim(), 'container_port': int.tryParse(containerPort.text.trim()) ?? containerPort.text.trim(), 'type': 'tcp'},
              ];
            }
            if (hostPath.text.trim().isNotEmpty && containerPath.text.trim().isNotEmpty) {
              profile['volumes'] = [
                {'host_dir': hostPath.text.trim(), 'container_dir': containerPath.text.trim(), 'type': 'bind'},
              ];
            }
            final envLines = env.text.split('\n').where((line) => line.contains('=')).toList();
            if (envLines.isNotEmpty) {
              profile['env'] = envLines.map((line) {
                final index = line.indexOf('=');
                return {'key': line.substring(0, index).trim(), 'value': line.substring(index + 1).trim()};
              }).toList();
            }
            Navigator.pop(context);
            try {
              await context.read<AppState>().service!.dockerCreate(profile);
              if (mounted) showToast(context, '已创建 $containerName');
              await _load();
            } on DsmException catch (e) {
              if (mounted) showToast(context, e.message, icon: Icons.error_outline_rounded);
            }
          },
          child: const Text('创建容器'),
        ),
        const SizedBox(height: 8),
        Text(
          '创建失败通常表示镜像未拉取、端口/目录不可用，或当前 DSM 的 Container Manager 需要不同的参数格式。',
          style: context.texts.labelSmall?.copyWith(color: context.colors.textTertiary, height: 1.5),
        ),
      ],
    );
    name.dispose();
    hostPort.dispose();
    containerPort.dispose();
    hostPath.dispose();
    containerPath.dispose();
    env.dispose();
  }

  Future<void> _showLogs(DockerContainer container) async {
    showAppSheet(
      context,
      title: '容器日志',
      subtitle: container.name,
      children: [
        FutureBuilder<String>(
          future: context.read<AppState>().service!.dockerLogs(container.name),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
              );
            }
            final logs = snapshot.data ?? '无法读取日志';
            return SoftCard(
              shadow: false,
              color: context.colors.surfaceAlt,
              child: SizedBox(
                height: 360,
                child: SingleChildScrollView(
                  child: SelectableText(
                    logs.isEmpty ? '暂无日志' : logs,
                    style: context.texts.bodySmall?.copyWith(fontFamily: 'Consolas', fontSize: 11, height: 1.5),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  void _showContainerActions(DockerContainer container) {
    showAppSheet(
      context,
      title: container.name,
      subtitle: '${container.image}${container.ports.isEmpty ? '' : ' · ${container.ports}'}',
      children: [
        if (!container.isRunning)
          SheetAction(icon: Icons.play_arrow_rounded, label: '启动容器', onTap: () {
            Navigator.pop(context);
            _action(container, 'start');
          }),
        if (container.isRunning)
          SheetAction(icon: Icons.stop_rounded, label: '停止容器', onTap: () {
            Navigator.pop(context);
            _action(container, 'stop');
          }),
        SheetAction(icon: Icons.restart_alt_rounded, label: '重启容器', onTap: () {
          Navigator.pop(context);
          _action(container, 'restart');
        }),
        SheetAction(icon: Icons.article_outlined, label: '查看日志', onTap: () {
          Navigator.pop(context);
          _showLogs(container);
        }),
        SheetAction(
          icon: Icons.delete_outline_rounded,
          label: '删除容器',
          danger: true,
          onTap: () async {
            Navigator.pop(context);
            final ok = await showConfirm(context, title: '删除 ${container.name}？', message: '仅删除容器，不会删除挂载的数据卷。', confirmText: '删除', danger: true);
            if (ok) _action(container, 'delete');
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final running = _containers.where((c) => c.isRunning).length;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PageScaffold(
        child: Column(
          children: [
            DetailHeader(
              title: 'Docker',
              subtitle: _loading ? '正在读取容器' : '$running 个运行中 · ${_containers.length} 个容器 · ${_images.length} 个镜像',
              actions: [
                CircleIconButton(icon: Icons.download_rounded, onTap: _pull, size: 20),
                const SizedBox(width: 2),
                CircleIconButton(icon: Icons.add_rounded, onTap: _create, size: 21),
                const SizedBox(width: 2),
                CircleIconButton(icon: Icons.refresh_rounded, onTap: _load, size: 20),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
              child: Row(
                children: [
                  _TabPill(label: '容器 ${_containers.length}', selected: _tab == 0, onTap: () => setState(() => _tab = 0)),
                  const SizedBox(width: 8),
                  _TabPill(label: '镜像 ${_images.length}', selected: _tab == 1, onTap: () => setState(() => _tab = 1)),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
                  : _error != null
                      ? Center(
                          child: EmptyHint(
                            icon: Icons.cloud_off_rounded,
                            title: '无法读取 Docker',
                            subtitle: _error,
                            action: FilledButton(onPressed: _load, child: const Text('重试')),
                          ),
                        )
                      : _tab == 0
                          ? _buildContainers(c)
                          : _buildImages(c),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContainers(AppColors c) {
    if (_containers.isEmpty) {
      return EmptyHint(
        icon: Icons.widgets_rounded,
        title: '还没有容器',
        subtitle: '可以拉取镜像后创建容器',
        action: FilledButton(onPressed: _create, child: const Text('创建容器')),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: c.primary,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        itemCount: _containers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final container = _containers[index];
          final statusColor = container.isRunning ? c.success : (container.isError ? c.danger : c.textTertiary);
          return SoftCard(
            padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
            radius: 20,
            onTap: () => _showContainerActions(container),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: (container.isRunning ? c.primary : c.textTertiary).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.widgets_rounded, size: 21, color: container.isRunning ? c.primary : c.textTertiary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(container.name, style: context.texts.titleSmall?.copyWith(fontSize: 14.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Text(container.image, style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(width: 6, height: 6, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                          const SizedBox(width: 5),
                          Text(container.statusLabel, style: context.texts.labelSmall?.copyWith(color: statusColor, fontSize: 10.5)),
                          if (container.ports.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(container.ports, style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          ] else if (container.memory > 0) ...[
                            const SizedBox(width: 8),
                            Text('${formatBytes(container.memory)} · ${container.cpu.toStringAsFixed(1)}%', style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (_busy.contains(container.name))
                  const SizedBox(width: 24, height: 24, child: Padding(padding: EdgeInsets.all(3), child: CircularProgressIndicator(strokeWidth: 2)))
                else
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _action(container, container.isRunning ? 'stop' : 'start'),
                    icon: Icon(
                      container.isRunning ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded,
                      size: 24,
                      color: container.isRunning ? c.textSecondary : c.primary,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildImages(AppColors c) {
    if (_images.isEmpty) {
      return const EmptyHint(icon: Icons.image_rounded, title: '还没有镜像', subtitle: '点击右上角下载按钮拉取镜像');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      itemCount: _images.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final image = _images[index];
        return SoftCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          radius: 18,
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: c.purple.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.layers_rounded, size: 19, color: c.purple),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(image.displayName, style: context.texts.titleSmall?.copyWith(fontSize: 13.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text(formatBytes(image.size), style: context.texts.labelSmall?.copyWith(color: c.textTertiary, fontSize: 10.5)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TabPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TabPill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? c.primary : c.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: selected ? [BoxShadow(color: c.primary.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 4))] : c.cardShadow,
        ),
        child: Text(label, style: context.texts.labelMedium?.copyWith(fontSize: 12, color: selected ? Colors.white : c.textSecondary)),
      ),
    );
  }
}
