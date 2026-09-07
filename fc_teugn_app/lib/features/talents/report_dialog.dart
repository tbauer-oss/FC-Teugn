import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'talents_repository.dart';

Future<void> showTalentsReport(BuildContext context,
    TalentsRepository repository, String title, String content) async {
  bool busy = false;
  String? message;
  await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
                title: Text(title),
                scrollable: true,
                content: SizedBox(
                    width: 640,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SelectableText(content),
                          if (message != null) Text(message!)
                        ])),
                actions: [
                  TextButton(
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: content)),
                      child: const Text('Kopieren')),
                  FilledButton.icon(
                      icon: const Icon(Icons.picture_as_pdf),
                      label:
                          Text(busy ? 'PDF wird erstellt …' : 'Druckbares PDF'),
                      onPressed: busy
                          ? null
                          : () async {
                              update(() => busy = true);
                              try {
                                final result = await repository.dio
                                    .post<List<int>>('/talents/reports/print',
                                        data: {
                                          'title': title,
                                          'content': content
                                        },
                                        options: Options(
                                            responseType: ResponseType.bytes,
                                            extra: {'requireOnline': true}));
                                await FilePicker.saveFile(
                                    dialogTitle: 'Bericht speichern',
                                    fileName: 'FC-Teugn-Bericht.pdf',
                                    bytes: Uint8List.fromList(result.data!));
                                if (context.mounted) update(() => busy = false);
                              } catch (e) {
                                if (context.mounted) {
                                  update(() {
                                    busy = false;
                                    message = talentsError(e);
                                  });
                                }
                              }
                            }),
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Schließen'))
                ],
              )));
}
