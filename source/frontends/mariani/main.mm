//
//  main.mm
//  Mariani
//
//  Created by sh95014 on 12/27/21.
//

#import <Cocoa/Cocoa.h>
#import "argparser.h"
#import "programoptions.h"

common2::EmulatorOptions gEmulatorOptions;

int main(int argc, char * const argv[]) {
    // need to split the argv[] into two halves, one for AppleWin to ingest, and the
    // other for NSApplicationMain().
    int awArgc, macArgc;
    char **awArgv = (char **)malloc(sizeof(*awArgv) * argc);
    char **macArgv = (char **)malloc(sizeof(*macArgv) * argc);
    awArgv[0] = macArgv[0] = argv[0];
    awArgc = macArgc = 1;
    
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-NSDocumentRevisionsDebugMode") == 0 ||
            strcmp(argv[i], "-AppleLanguages") == 0 ||
            strcmp(argv[i], "-AppleTextDirection") == 0) {
            macArgv[macArgc++] = argv[i];
            if (i + 1 < argc) {
                macArgv[macArgc++] = argv[++i];
            }
        }
        else {
            awArgv[awArgc++] = argv[i];
        }
    }
    
    if (!getEmulatorOptions(awArgc, awArgv, common2::OptionsType::none, "macOS", gEmulatorOptions)) {
        return -1;
    }
    return NSApplicationMain(macArgc, (const char **)macArgv);
}
