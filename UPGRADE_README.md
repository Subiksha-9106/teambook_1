# TeamBook - Upgraded Flutter Project

This ZIP contains the existing TeamBook Flutter project with the requested features merged into `lib/main.dart`.

## Included features
- Quick contact actions (call, email, copy, share)
- Dashboard summaries and department/job-role breakdowns
- Search, combined filters, sorting, and clear filters
- Favourites and recently viewed profiles
- CSV export for filtered employee lists
- Admin form validation, duplicate-email warning, delete confirmation, and status messages

## Run
1. Extract this ZIP.
2. Open the `TeamBook_Flutter_Mobile_Source` folder in VS Code.
3. Run `flutter pub get`.
4. Run `flutter analyze`, then `flutter run`.
5. To build Android APK, run `flutter build apk --release`.

The API used by the original project may simulate add/edit/delete operations; local app data persistence remains limited to the existing implementation. This source has not been compiled in this packaging environment, so run the commands above and review any reported errors.
