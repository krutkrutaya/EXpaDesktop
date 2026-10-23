// A request for the in-app Files window to pick one file. Used by Configs to
// choose a .zip preset pack; a "Use" button appears only on matching rows and
// the rest of the browser stays a browser.

class FilePickRequest {
  final String title;
  final bool Function(String path) accepts;
  final void Function(String path) onPick;
  final void Function()? onCancel;

  const FilePickRequest({
    required this.title,
    required this.accepts,
    required this.onPick,
    this.onCancel,
  });
}