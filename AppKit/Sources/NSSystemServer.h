//
//  NSSystemServer.h
//  mySTEP / AppKit
//
//  Private interfaces used internally in AppKit implementation only
//  to communicate with a single, shared loginwindow process to provide
//  global services (e.g. list of all applications, inking etc.)
//
//  Created by Dr. H. Nikolaus Schaller on Thu Jan 05 2006.
//  Copyright (c) 2006 DSITRI. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <AppKit/NSApplication.h>
#import <AppKit/NSSound.h>
#import <AppKit/NSWorkspace.h>

@protocol _NSApplicationRemoteControlProtocol	// basic communication of workspace server with any application

- (BOOL) _application:(in NSApplication *) app openURLs:(in bycopy NSArray *) urls withOptions:(in bycopy NSWorkspaceLaunchOptions) opts;	// handle open
- (void) activate;
- (void) deactivate;
- (void) hide;
- (void) unhide;
- (void) echo;

@end

#define NSWorkspaceServerPort @"com.quantum-step.loginwindow"	// NSMessagePort to contact

@protocol _NSWorkspaceServerProtocol	// communication with system UI (which should be the loginwindow process)

	/* system menu */

- (oneway void) showShutdownDialog;
- (oneway void) showRestartDialog;
- (oneway void) showForceQuitDialog;	// show the force-quit dialog
- (oneway void) reallyLogout;			// immediately log out
- (oneway void) logout;					// request a logout
- (oneway void) shutdown;				// request a shutdown
- (oneway void) restart;				// request a restart
- (oneway void) sleep;					// request to sleep
- (oneway void) showAboutPanel;			// show About panel
- (oneway void) showSoftwareUpdater;
- (oneway void) showKillApplications;	// show Applications list panel

	/* system wide sound generator */

- (bycopy NSArray *) soundFileTypes;
- (oneway void) play:(byref NSSound *) sound;	// mix sound into currently playing sounds or schedule to end of queue
- (oneway void) pause:(byref NSSound *) sound;
- (oneway void) resume:(byref NSSound *) sound;
- (oneway void) stop:(byref NSSound *) sound;
- (BOOL) isPlaying:(byref NSSound *) sound;

	/* global window list / window levels */

- (int []) windowList;
- (int []) windowsAtLevel:(int) level;

	/* request&cancel user attention for a given application */

- (int) requestUserAttention:(NSRequestUserAttentionType) requestType forApplication:(byref NSApplication *) app;
- (oneway void) cancelUserAttentionRequest:(int) request;

	/* system wide inking service */

- (oneway void) startInkingForApplication:(byref NSApplication *) app atScreenPosition:(NSPoint) point;	// calls back [app postEvent:] with keyboard events

- (oneway void) enableASR:(BOOL) flag;	// enable/disable automatic speech recognition
- (oneway void) enableOCR:(BOOL) flag;	// enable/disable OCR
- (oneway void) enableVKBD:(BOOL) flag;	// enable/disable virtual keyboard

@end

@interface NSWorkspace (NSWorkspaceServer)

+ (id <_NSWorkspaceServerProtocol>) _systemUIServer;	// get distributed object to contact loginwindow

@end