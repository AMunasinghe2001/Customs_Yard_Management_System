#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // A named mutex the INSTALLER looks for, so it can tell whether this app
  // is running before it tries to replace the files.
  //
  // Without it, Inno Setup falls back to the Restart Manager, which does
  // not reliably close a Flutter window. The install then failed partway
  // through with
  //
  //     C:\Program Files\...uto_updater_windows_plugin.dll
  //     DeleteFile failed; code 5. Access is denied.
  //
  // because Windows locks the DLLs of a running process -- and the officer
  // was asked to choose between "Try again", "Skip this file" and "Cancel",
  // none of which is safe: skipping leaves a half-updated install.
  //
  // The name must match AppMutex in installer/setup.iss EXACTLY.
  //
  // Global\ so it is visible across sessions: an app left running under
  // another logged-in account locks the files just the same, and a
  // session-local name would miss it.
  //
  // The handle is deliberately never closed -- it is released when the
  // process ends, which is precisely when the installer may proceed.
  ::CreateMutexW(nullptr, FALSE, L"Global\\SLCustomsSRManagementSystem");

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Sri Lanka Customs Inventory Management System", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
