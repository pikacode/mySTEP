//
//  MKMapView.m
//  MapKit
//
//  Created by H. Nikolaus Schaller on 20.10.09.
//  Copyright 2009 Golden Delicious Computers GmbH&Co. KG. All rights reserved.
//

#import <MapKit/MapKit.h>

#define TILEPIXELS	256.0

@interface _MKTile : NSObject
{
	NSURL *_url;
	NSURLConnection *_connection;
	NSMutableData *_data;
	NSImage *_image;
	MKMapView *_delegate;
}

// FIXME: what about multiple MapViews?

- (id) initWithContentsOFURL:(NSURL *) url forView:(MKMapView *) delegate;
- (void) start;
- (NSImage *) image;
@end

@implementation _MKTile

static NSMutableArray *loadQueue;	// TileLoaders to be started
static int alreadyLoading=0;

- (id) initWithContentsOFURL:(NSURL *) url forView:(MKMapView *) delegate;
{
	if((self=[super init]))
		{
		_delegate=[delegate retain];
		_url=[url retain];
		if(alreadyLoading == 0)
			[[_delegate delegate] mapViewWillStartLoadingMap:_delegate];
		if(alreadyLoading < 5)
			[self start];
		else
			{ // enqueue
				if(!loadQueue)
					loadQueue=[[NSMutableArray alloc] initWithCapacity:20];
				[loadQueue addObject:self];	// put into queue
			}
		}
	return self;
}

- (void) start
{
	if(!_connection)
		{
		_connection=[[NSURLConnection connectionWithRequest:[NSURLRequest requestWithURL:_url] delegate:self] retain];
		[_url release];
		_url=nil;
		[_connection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSEventTrackingRunLoopMode];
		alreadyLoading++;
		[loadQueue removeObjectIdenticalTo:self];	// and remove (if we are in the queue)
		}
}

- (void) connection:(NSURLConnection *) connection didReceiveData:(NSData *) data
{
	if(!_data)
		_data=[data mutableCopy];
	else
		[_data appendData:data];
}

- (void) connection:(NSURLConnection *) connection didFailWithError:(NSError *) error
{
#if 1
	NSLog(@"didFailWithError: %@", error);
#endif
#if 0
	_image=[[NSImage alloc] initWithSize:NSMakeSize(TILEPIXELS, TILEPIXELS)];	// write error message into a tile
	[_image setFlipped:NO];
	[_image lockFocus];
	[[error localizedDescription] drawInRect:[_image alignmentRect] withAttributes:nil];
	[_image unlockFocus];
#endif
	[self connectionDidFinishLoading:connection];
}

- (void) connectionDidFinishLoading:(NSURLConnection *) connection
{
	[_connection release];
	_connection=nil;
	if(!_image && _data)
		{ // get image from data (unless we show an error message)
		_image=[[NSImage alloc] initWithData:_data];
//		[_image setFlipped:YES];
		}
	[_data release];
	_data=nil;
	[_delegate setNeedsDisplay:YES];	// and redisplay (we should specify a rect where we want to be updated)
	alreadyLoading--;
	NSAssert(alreadyLoading >= 0, @"never become negative");
	if([loadQueue count] > 0)
		[[loadQueue lastObject] start];	// will remove self
	else if(alreadyLoading == 0)
		[[_delegate delegate] mapViewDidFinishLoadingMap:_delegate];
}

- (NSImage *) image;
{
	if(_url)
		{
		if([loadQueue lastObject] != self)
			{ // LRU handling
				[loadQueue removeObjectIdenticalTo:self];
				[loadQueue addObject:self];
			}
		return nil;
		}
	if(_connection)
		return nil;	// already/still loading
	return _image;
}

- (void) dealloc
{
	[_connection cancel];
	[_connection release];
	[_delegate release];
	[_data release];
	[_image release];
	[_url release];
	[super dealloc];
}

@end

static MKMapRect _MKMapRectForCoordinateRegion(MKCoordinateRegion reg)
{ // convert corner points (may have different center!)
	MKMapPoint sw=MKMapPointForCoordinate((CLLocationCoordinate2D) { reg.center.latitude-0.5*reg.span.latitudeDelta, reg.center.longitude-0.5*reg.span.longitudeDelta });
	MKMapPoint ne=MKMapPointForCoordinate((CLLocationCoordinate2D) { reg.center.latitude+0.5*reg.span.latitudeDelta, reg.center.longitude+0.5*reg.span.longitudeDelta });
	return (MKMapRect) { sw, (MKMapSize) { ne.x-sw.x, ne.y-sw.y }};
}

@implementation MKMapView

static MKMapRect worldMap;	// visible map rect at z=0 (topmost tile)

#define CACHESIZE 100

static NSMutableDictionary *imageCache;
static NSMutableArray *tileLRU;

+ (void) initialize
{
	if(self == [MKMapView class])
		{
		MKMapPoint topRight=MKMapPointForCoordinate((CLLocationCoordinate2D) { 85.0, 180.0-1e-12 });	// CLLocationCoordinate2D is (latitude, longigude) which corresponds to (y, x)
#if 1	// for testing...
		CLLocationCoordinate2D test=MKCoordinateForMapPoint(topRight);
		if(test.latitude != 85.0 || test.longitude != 180.0-1e-12)
			{
			NSLog(@"conversion error");
			topRight=MKMapPointForCoordinate((CLLocationCoordinate2D) { 85.0, 180.0 });	// CLLocationCoordinate2D is (latitude, longigude) which corresponds to (y, x)
			test=MKCoordinateForMapPoint(topRight);
			}
#endif
		worldMap.origin=MKMapPointForCoordinate((CLLocationCoordinate2D) { -85.0, -180.0  });
		worldMap.size.width=topRight.x - worldMap.origin.x;
		worldMap.size.height=topRight.y - worldMap.origin.y;
		imageCache=[[NSMutableDictionary alloc] initWithCapacity:CACHESIZE];
		tileLRU=[[NSMutableArray alloc] initWithCapacity:CACHESIZE];
		}
}

- (id) initWithFrame:(NSRect) frameRect
{
	if((self=[super initWithFrame:frameRect]))
		{
		annotations=[[NSMutableArray alloc] initWithCapacity:50];
		overlays=[[NSMutableArray alloc] initWithCapacity:20];
		visibleMapRect=[self mapRectThatFits:worldMap];	// start with world map
		scrollEnabled=YES;
		zoomEnabled=YES;
		[self setShowsUserLocation:YES];
		}
	return self;
}

- (void) setFrame:(NSRect) frameRect
{ // adjust aspect ratio
#if 1
	NSRect frame=[self frame];
	float fx=frameRect.size.width / frame.size.width;
	float fy=frameRect.size.height / frame.size.height;
	// adjust for movement of frame.origin!
	visibleMapRect.origin.x += 0.5*visibleMapRect.size.width;	// keep center stable
//	visibleMapRect.origin.x *= fx;
	visibleMapRect.size.width *= fx;
	visibleMapRect.origin.x -= 0.5*visibleMapRect.size.width;	// new left edge
	visibleMapRect.origin.y -= 0.5*visibleMapRect.size.height;
//	visibleMapRect.origin.y *= fy;
	visibleMapRect.size.height *= fy;
	visibleMapRect.origin.y += 0.5*visibleMapRect.size.height;
#endif
	[super setFrame:frameRect];
	[self setNeedsDisplay:YES];
}

- (void) setFrameSize:(NSSize) newSize
{
#if 1
	NSRect frame=[self frame];
	float fx=newSize.width / frame.size.width;
	float fy=newSize.height / frame.size.height;
	visibleMapRect.origin.x += 0.5*visibleMapRect.size.width;	// keep center stable
//	visibleMapRect.origin.x *= fx;
	visibleMapRect.size.width *= fx;
	visibleMapRect.origin.x -= 0.5*visibleMapRect.size.width;	// new left edge
	visibleMapRect.origin.y -= 0.5*visibleMapRect.size.height;
//	visibleMapRect.origin.y *= fy;
	visibleMapRect.size.height *= fy;
	visibleMapRect.origin.y += 0.5*visibleMapRect.size.height;
#endif
	[super setFrameSize:newSize];
	[self setNeedsDisplay:YES];
}

- (id) initWithCoder:(NSCoder *) aDecoder;
{
	self=[super initWithCoder:aDecoder];
	// delegate?
	// visibleMapRect?
	// scrollEnabled
	// [self setShowsUserLocation:[aDecoder boolForKey:@"key"]];
	// zoomEnabled
	return self;
}

- (void) dealloc;
{
	[annotations release];
	[overlays release];
	[userLocation release];
	[super dealloc];
}

- (BOOL) isOpaque; { return YES; }
// - (BOOL) isFlipped; { return YES; }
- (BOOL) acceptsFirstResponder { return YES; }	// otherwise we don't receive keyboard and arrow key events/actions


// FIXME: we could define a NSAffineTransform that we update parallel to changes of bounds and visibleMapRect

- (NSPoint) _pointForMapPoint:(MKMapPoint) pnt
{ // convert map point to bounds point (using visibleMapRect)
	NSRect bounds=[self bounds];
	MKMapRect visible=[self visibleMapRect];
	return NSMakePoint(NSMinX(bounds)+NSWidth(bounds)*(pnt.x-MKMapRectGetMinX(visible))/MKMapRectGetWidth(visible),
					   NSMinY(bounds)+NSHeight(bounds)*(pnt.y-MKMapRectGetMinY(visible))/MKMapRectGetHeight(visible));
}

- (NSRect) _rectForMapRect:(MKMapRect) rect
{ // convert map rect to bounds rect (using visibleMapRect)
	NSRect bounds=[self bounds];
	MKMapRect visible=[self visibleMapRect];
	return NSMakeRect(NSMinX(bounds)+NSWidth(bounds)*(MKMapRectGetMinX(rect)-MKMapRectGetMinX(visible))/MKMapRectGetWidth(visible),
					  NSMinY(bounds)+NSHeight(bounds)*(MKMapRectGetMinY(rect)-MKMapRectGetMinY(visible))/MKMapRectGetHeight(visible),
					  NSWidth(bounds)*MKMapRectGetWidth(rect)/MKMapRectGetWidth(visible),
					  NSHeight(bounds)*MKMapRectGetHeight(rect)/MKMapRectGetHeight(visible)
					  );
}

- (MKMapPoint) _mapPointForPoint:(NSPoint) pnt
{ // convert map point to bounds point (using visibleMapRect)
	NSRect bounds=[self bounds];
	MKMapRect visible=[self visibleMapRect];
	return MKMapPointMake(MKMapRectGetMinX(visible)+MKMapRectGetWidth(visible)*(pnt.x-NSMinX(bounds))/NSWidth(bounds),
						  MKMapRectGetMinY(visible)+MKMapRectGetHeight(visible)*(pnt.y-NSMinY(bounds))/NSHeight(bounds));
}

- (MKMapRect) _mapRectForRect:(NSRect) rect
{ // convert map rect to bounds rect (using visibleMapRect)
	NSRect bounds=[self bounds];
	MKMapRect visible=[self visibleMapRect];
	return MKMapRectMake(MKMapRectGetMinX(visible)+MKMapRectGetWidth(visible)*(NSMinX(rect)-NSMinX(bounds))/NSWidth(bounds),
						 MKMapRectGetMinY(visible)+MKMapRectGetHeight(visible)*(NSMinY(rect)-NSMinY(bounds))/NSHeight(bounds),
						 NSWidth(rect)*MKMapRectGetWidth(visible)/NSWidth(bounds),
						 NSHeight(rect)*MKMapRectGetHeight(visible)/NSHeight(bounds)
						 );
}

// FIXME: how does resizing modify the visibleMapRect?
// we must overwrite setFrame(Size) and adjust the visibleRect

- (NSString *) tileURLForZ:(int) z x:(int) x y:(int) y;
{ // conversion of geo location and zoom into Mapnik tile path: http://wiki.openstreetmap.org/wiki/Slippy_map_tilenames
	long iscale;
	if(z < 0 || z > 20)
		return nil;
	iscale = 1<<z;
	x %= iscale;	// repeat tile pattern if we wrap around the map
	if(x < 0) x += iscale;	// c99 defines negative return value for negative dividend and we need the modulus
	y %= iscale;
	if(y < 0) y += iscale;
	switch(mapType) {
		// ignored
	}
	return [NSString stringWithFormat:@"http://tile.openstreetmap.org/%d/%d/%d.png", z, x, y];
}

- (BOOL) drawTileForZ:(int) z x:(int) x y:(int) y intoRect:(NSRect) rect load:(BOOL) flag;
{ // draw tile in required zoom at given position if it intersects the rect
	float iscale = exp2(-z);
	MKMapSize tileSize = (MKMapSize) { worldMap.size.width * iscale, worldMap.size.height * iscale };	// size of single tile (at scale z)
	MKMapRect mapRect = MKMapRectMake(x*tileSize.width, y*tileSize.height, tileSize.width, tileSize.height);
	NSRect drawRect = [self _rectForMapRect:mapRect];	// transform tile
	NSString *url;
	_MKTile *tile;
	NSImage *img;	
	if(!NSIntersectsRect(drawRect, rect))
		return NO;	// tile does not fall into drawing rect
	url=[self tileURLForZ:z x:x y:y];	// repeat tiles if necessary
	if(!url || !(tile=[imageCache objectForKey:url]))	// check if we already cache this tile
		{ // not in cache - try larger or smaller tiles and trigger tile loader
			// problem with larger tiles: must be drawn before we draw any other smaller one!
			// i.e. we must sort according to z and draw any lower z before this z!
			if(!flag)
				return NO;	// and don't load
			if(url)
				{
				// start tile loader
				// if we add the first tile to load, call [delegate didStartLoading]
				// for each tile that arrives, call setNeedsDisplayInRect:
				// when the last tile arrives, call [delegate didFinishLoading]
				NSLog(@"loading %@", url);
				tile=[[[_MKTile alloc] initWithContentsOFURL:[NSURL URLWithString:url] forView:self] autorelease];
				[imageCache setObject:tile forKey:url];
				if([tileLRU count] > CACHESIZE)
					[tileLRU removeLastObject];	// remove least recently used tile
				}
			else
				tile=nil;
		}
	else
		[tileLRU removeObject:tile];
	img=[tile image];
	if(img)
		[tileLRU insertObject:tile atIndex:0];  // move to beginning of LRU list
#if 1
	NSLog(@"drawTile z=%d x=%d y=%d into %@ %@", z, x, y, NSStringFromRect(drawRect), [tile image]);
#endif
	[img drawInRect:drawRect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
#if 1
	if(img)
		[[NSColor greenColor] set];
	else
		[[NSColor redColor] set];
	NSFrameRect(drawRect);	// draw a box around the tile
#endif
	return img != nil;
}

- (void) drawRect:(NSRect) rect
{
	MKZoomScale scale = MIN(worldMap.size.width / visibleMapRect.size.width, worldMap.size.height / visibleMapRect.size.height);
	float lscale=log2(scale);
	int z=ceil(lscale);	// basic scale
	float iscale = exp2(z);	// scale factor
	MKMapRect r=[self _mapRectForRect:rect];
	int minx=floor(iscale*MKMapRectGetMinX(r) / worldMap.size.width);	// get tile index range at zoom z
	int maxx=ceil(iscale*MKMapRectGetMaxX(r) / worldMap.size.width);
	int miny=floor(iscale*MKMapRectGetMinY(r) / worldMap.size.height);
	int maxy=ceil(iscale*MKMapRectGetMaxY(r) / worldMap.size.height);
	int x, y;
	
	[[NSColor controlColor] set];
	NSRectFill(rect);	// draw grey background
	
	// optionally draw a meridian or tile grid?
	
#if 1
	{
	NSString *str=@"I am the MKMapView\n";
	str=[str stringByAppendingFormat:@"%@\n", [annotations description]];
	str=[str stringByAppendingFormat:@"%@\n", MKStringFromMapRect(visibleMapRect)];
	str=[str stringByAppendingFormat:@"%@\n", MKStringFromMapRect(worldMap)];
	[str drawInRect:NSMakeRect(10.0, 10.0, 1000.0, 300.0) withAttributes:nil];
	}
#endif	

	for(y = miny; y < maxy; y++)
		{
		for(x = minx; x < maxx; x++)
			{
			// draw lower resolution background if available
			// but make sure we draw each z-value only once!
			if(![self drawTileForZ:z x:x y:y intoRect:rect load:YES])
				{ // did not draw - stich together from higher resolution
#if 0
					// FIXME: should this go recursively?
					// to a defined number of levels? Or just be limited by tile size?
					[self drawTileForZ:z+1 x:2*x y:2*y intoRect:rect load:NO];
					[self drawTileForZ:z+1 x:2*x+1 y:2*y intoRect:rect load:NO];
					[self drawTileForZ:z+1 x:2*x y:2*y+1 intoRect:rect load:NO];
					[self drawTileForZ:z+1 x:2*x+1 y:2*y+1 intoRect:rect load:NO];
#endif
				}
			}
		}
	/* draw annotations and overlays (not here - they are handled through subviews) */
	// we should check annotation views if they are still visible
	//
}

- (void) addAnnotation:(id <MKAnnotation>) a; { [annotations addObject:a]; [self setNeedsDisplay:YES]; }	// could optimize drawing rect?
- (void) addAnnotations:(NSArray *) a; { [annotations addObjectsFromArray:a]; [self setNeedsDisplay:YES]; }
- (void) addOverlay:(id <MKOverlay>) o; { [overlays addObject:o]; [self setNeedsDisplay:YES]; }
- (void) addOverlays:(NSArray *) o; { [overlays addObjectsFromArray:o]; [self setNeedsDisplay:YES]; }
- (NSArray *) annotations;{ return annotations; }

- (NSRect) annotationVisibleRect;
{
	NSRect r=NSZeroRect;
	// loop over all visible annotations and r=NSUnionRect(r, [annotation frame]);
	return r;
}

- (CLLocationCoordinate2D) centerCoordinate; { return MKCoordinateRegionForMapRect(visibleMapRect).center; }

- (NSPoint) convertCoordinate:(CLLocationCoordinate2D) coord toPointToView:(UIView *) view;
{
	MKMapPoint pnt=MKMapPointForCoordinate(coord);
	NSPoint p=[self _pointForMapPoint:pnt];	// map to point
	return [self convertPoint:p toView:view];
}

- (CLLocationCoordinate2D) convertPoint:(NSPoint) point toCoordinateFromView:(UIView *) view;
{
	NSPoint pnt=[self convertPoint:point fromView:view];
	MKMapPoint p=[self _mapPointForPoint:pnt];
	return MKCoordinateForMapPoint(p);
}

- (MKCoordinateRegion) convertRect:(NSRect) coord toRegionFromView:(UIView *) view;
{
	NSRect rect=[self convertRect:coord fromView:view];
	MKMapRect r=[self _mapRectForRect:rect];
	return MKCoordinateRegionForMapRect(r);	// FIXME: this function is not completely implemented
}

- (NSRect) convertRegion:(MKCoordinateRegion) region toRectToView:(UIView *) view;
{
/* FIXME: this is not well defined since there is no MKMapRectForCoordinateRegion function - and the rect becomes distorted
 We may have to take the center of the region and apply the span uniformly
 
	MKMapRect rect=MKMapRectForCoordinateRegion(region);
	NSRect r=[self _rectForMapRect:rect];	// map to point
	return [self convertRect:r toView:view];	
 */
	return NSZeroRect;
}

- (id <MKMapViewDelegate>) delegate; { return delegate; }

- (MKAnnotationView *) dequeueReusableAnnotationViewWithIdentifier:(NSString *) ident;
{ // not yet implemented
	// can we have multiple views with same ident?
	// if yes, we need a NSDictionary with NSMutableArray entries
	// this method looks if we have such an identifier
	return nil;
}

- (void) _enqueueReusableAnnotationView:(MKAnnotationView *) view
{ // has moved off-screen
	NSString *ident=[view reuseIdentifier];
	if(ident)
		{ // put into queue
		
		}
}

- (void) deselectAnnotation:(id <MKAnnotation>) a animated:(BOOL) flag;
{
	[[self viewForAnnotation:a] setSelected:NO animated:flag];
}

- (void) exchangeOverlayAtIndex:(NSUInteger) idx1 withOverlayAtIndex:(NSUInteger) idx2; { [overlays exchangeObjectAtIndex:idx1 withObjectAtIndex:idx2]; [self setNeedsDisplay:YES]; }

- (void) insertOverlay:(id <MKOverlay>) o aboveOverlay:(id <MKOverlay>) sibling;
{ // search 
	NSUInteger idx=[overlays indexOfObject:sibling];
	if(idx == NSNotFound)
		; // raise exception
	[self insertOverlay:o atIndex:idx+1];
}

- (void) insertOverlay:(id <MKOverlay>) o atIndex:(NSUInteger) idx; { [overlays insertObject:o atIndex:idx]; [self setNeedsDisplay:YES]; }

- (void) insertOverlay:(id <MKOverlay>) o belowOverlay:(id <MKOverlay>) sibling;
{ // search  
	NSUInteger idx=[overlays indexOfObject:sibling];
	if(idx == NSNotFound)
		; // raise exception
	[self insertOverlay:o atIndex:idx];
}

- (BOOL) isScrollEnabled; { return scrollEnabled; }

- (BOOL) isUserLocationVisible;
{
	if(!userLocation)
		return NO;
	// use horizontal accuracy and current location to check if the user location is (at least) partially on screen
	return YES;
}

- (BOOL) isZoomEnabled; { return zoomEnabled; }

- (MKMapRect) mapRectThatFits:(MKMapRect) rect;
{
	UIEdgeInsets insets = { 0, 0, 0, 0 };
	return [self mapRectThatFits:rect edgePadding:insets];
}

- (MKMapRect) mapRectThatFits:(MKMapRect) rect edgePadding:(UIEdgeInsets) insets;
{
	NSRect frame=[self frame];
	// adjust frame by insets
	float fx=rect.size.width / frame.size.width;
	float fy=rect.size.height / frame.size.height;
	if(fx > fy)
		{ // wider than screen - cut left&right
			rect.origin.x += 0.5*rect.size.width;	// keep center stable
			rect.origin.x *= fy/fx;
			rect.size.width *= fy/fx;
			rect.origin.x -= 0.5*rect.size.width;	// new left edge			
		}
	else
		{ // higher than screen - cut top&bottom
			rect.origin.y -= 0.5*rect.size.height;
			rect.origin.y *= fx/fy;
			rect.size.height *= fx/fy;
			rect.origin.y += 0.5*rect.size.height;			
		}
	return rect;
}

- (MKMapType) mapType; { return mapType; }
- (NSArray *) overlays; { return overlays; }
- (MKCoordinateRegion) region; { return MKCoordinateRegionForMapRect(visibleMapRect); }

- (MKCoordinateRegion) regionThatFits:(MKCoordinateRegion) region;
{
	return MKCoordinateRegionForMapRect([self mapRectThatFits:_MKMapRectForCoordinateRegion(region)]);
}

- (void) removeAnnotation:(id <MKAnnotation>) a; { [annotations removeObjectIdenticalTo:a]; [self setNeedsDisplay:YES]; }
- (void) removeAnnotations:(NSArray *) a; { [annotations removeObjectsInArray:a]; [self setNeedsDisplay:YES]; }
- (void) removeOverlay:(id <MKOverlay>) a; { [overlays removeObjectIdenticalTo:a]; [self setNeedsDisplay:YES]; }
- (void) removeOverlays:(NSArray *) a; { [overlays removeObjectsInArray:a]; [self setNeedsDisplay:YES]; }

- (void) selectAnnotation:(id <MKAnnotation>) a animated:(BOOL) flag;
{
	[[self viewForAnnotation:a] setSelected:YES animated:flag];
}

- (NSArray *) selectedAnnotations;
{
	NSMutableArray *r=[NSMutableArray arrayWithCapacity:10];
	NSEnumerator *e=[annotations objectEnumerator];
	id <MKAnnotation> a;
	while((a=[e nextObject]))
		  { // go through annotation views and check isSelected
		  if([[self viewForAnnotation:a] isSelected])
			  [r addObject:a];
		  }
	return r;
}

- (void) setCenterCoordinate:(CLLocationCoordinate2D) center;
{
	[self setCenterCoordinate:center animated:NO];
}

- (void) setCenterCoordinate:(CLLocationCoordinate2D) center animated:(BOOL) flag;
{ // keep zoom constant and just move center
	MKMapRect visible=[self visibleMapRect];
	MKMapPoint newCenter=MKMapPointForCoordinate(center);
	visible=MKMapRectMake(newCenter.x-0.5*MKMapRectGetWidth(visible), newCenter.x-0.5*MKMapRectGetHeight(visible), MKMapRectGetWidth(visible), MKMapRectGetHeight(visible));
	[self setVisibleMapRect:visible animated:flag];	// show new map rect
}

- (void) setDelegate:(id <MKMapViewDelegate>) d; { delegate=d; }
- (void) setMapType:(MKMapType) type; { mapType=type; [self setNeedsDisplay:YES]; }

- (void) setRegion:(MKCoordinateRegion) reg;
{
	[self setRegion:reg animated:NO];
}

- (void) setRegion:(MKCoordinateRegion) reg animated:(BOOL) flag;
{
	MKMapRect visible=[self mapRectThatFits:_MKMapRectForCoordinateRegion(reg)];
	[self setVisibleMapRect:visible animated:flag];
}

- (void) setScrollEnabled:(BOOL) flag; { scrollEnabled=flag; }

- (void) setSelectedAnnotation:(NSArray *) a;
{ // copy property
	[annotations autorelease];
	annotations=[a copy];
	// select them all
}

- (void) setShowsUserLocation:(BOOL) flag;
{
	flag = (flag != 0);
	if(showsUserLocation != flag)
		{ // changes
			if((showsUserLocation=flag))
				{
				[delegate mapViewWillStartLocatingUser:self];
				userLocation=[MKUserLocation new];	// create
				[self addAnnotation:userLocation];
				}
			else
				{
				[self removeAnnotation:userLocation];
				[userLocation release];
				userLocation=nil;				
				[delegate mapViewDidStopLocatingUser:self];
				}
		}
}

- (void) setUserLocationVisible:(BOOL) flag; { userLocationVisible=flag; [self setNeedsDisplay:YES]; }

- (void) setVisibleMapRect:(MKMapRect) rect;
{
//	rect=[self mapRectThatFits:rect edgePadding:insets];
	visibleMapRect=rect;
	// update annotation an overlay views
	[self setNeedsDisplay:YES];
}

- (void) setVisibleMapRect:(MKMapRect) rect animated:(BOOL) flag;
{
	if(flag)
		{
		// animate by defining a timer and the delta
		}
	[self setVisibleMapRect:rect];
}

- (void) setVisibleMapRect:(MKMapRect) rect edgePadding:(UIEdgeInsets) insets animated:(BOOL) flag;
{
	rect=[self mapRectThatFits:rect edgePadding:insets];
	[self setVisibleMapRect:rect animated:flag];
}

- (void) setZoomEnabled:(BOOL) flag; { zoomEnabled=flag; }
- (BOOL) showsUserLocation; { return showsUserLocation; }
- (MKUserLocation *) userLocation; { return userLocation; }

- (MKAnnotationView *) viewForAnnotation:(id <MKAnnotation>) a;
{
	// check queue/cache
	MKAnnotationView *v=[delegate mapView:self viewForAnnotation:a];
	if(!v)
		{ // use default view
		
		}
	return v;
}

- (MKOverlayView *) viewForOverlay:(id <MKOverlay>) o;
{
	// check queue/cache
	MKOverlayView *v=[delegate mapView:self viewForOverlay:o];
	return v;	
}

- (MKMapRect) visibleMapRect; { return visibleMapRect; }

- (void) _scaleBy:(float) factor
{
	if(zoomEnabled)
		{
		MKMapRect v=[self visibleMapRect];
		v.origin.x += 0.5*v.size.width;		// old center
		v.origin.y += 0.5*v.size.height;
		v.size.width *= factor;
		v.size.height *= factor;
		v.origin.x -= 0.5*v.size.width;		// new left corner
		v.origin.y -= 0.5*v.size.height;	// new bottom corner
		[self setVisibleMapRect:v animated:YES];			
		}
}

- (void) _moveByX:(double) x Y:(double) y;
{
	if(scrollEnabled)
		{
		MKMapRect v=[self visibleMapRect];
		v.origin.x += x;
		v.origin.y += y;
		[self setVisibleMapRect:v animated:YES];		
		}
}

- (IBAction) zoomIn:(id) sender;
{
	[self _scaleBy:0.5];
}

- (IBAction) zoomOut:(id) sender;
{
	[self _scaleBy:2.0];
}

- (IBAction) moveLeft:(id) sender;
{
	if(([[NSApp currentEvent] modifierFlags] & NSAlternateKeyMask) != 0)
		[self _scaleBy:1.0/0.9];
	else
		[self _moveByX:-0.1*[self visibleMapRect].size.width Y:0.0];
}

- (IBAction) moveRight:(id) sender;
{
	if(([[NSApp currentEvent] modifierFlags] & NSAlternateKeyMask) != 0)
		[self _scaleBy:0.9];
	else
		[self _moveByX:+0.1*[self visibleMapRect].size.width Y:0.0];
}

- (IBAction) moveUp:(id) sender;
{
	if(([[NSApp currentEvent] modifierFlags] & NSAlternateKeyMask) != 0)
		[self _scaleBy:0.9];
	else
		[self _moveByX:0.0 Y:+0.1*[self visibleMapRect].size.height];
}

- (IBAction) moveDown:(id) sender;
{
	if(([[NSApp currentEvent] modifierFlags] & NSAlternateKeyMask) != 0)
		[self _scaleBy:1.0/0.9];
	else
		[self _moveByX:0.0 Y:-0.1*[self visibleMapRect].size.height];
}

- (void) scrollWheel:(NSEvent *) event;
{ // scroll or zoom
	if(([event modifierFlags] & NSAlternateKeyMask) != 0)
		{ // soft zoom in/out
			[self _scaleBy:pow(1.1, [event deltaY])];
		}
	else
		{
		NSRect r=(NSRect) { NSZeroPoint, { [event deltaX], [event deltaY] } };	// rect with 1x1 px
		MKMapRect m=[self _mapRectForRect:r];	// get offset
		[self _moveByX:m.size.width Y:m.size.height];
		}
}

- (void) mouseDown:(NSEvent *)theEvent;
{ // we come here only if hitTest of MKAnnotationViews and MKOverlayViews did fail
	NSPoint p0 = [self convertPoint:[theEvent locationInWindow] fromView:nil];	// initial point
	MKMapPoint pnt = [self _mapPointForPoint:p0];	// where did we click on the Mercator map?
	MKMapPoint speed = { 0.0, 0.0 };
#if 1
	CLLocationCoordinate2D latlong=MKCoordinateForMapPoint(pnt);
	NSLog(@"NSControl mouseDown point=%@", NSStringFromPoint(p0));
	NSLog(@"  MKMapPoint %@", MKStringFromMapPoint(pnt));
	NSLog(@"  MKCoordinate %@", [NSString stringWithFormat:@"{lat=%g,lng=%g}", latlong.latitude, latlong.longitude]);
#endif
	if([theEvent clickCount] > 1)
		{ // was a double click - center + zoom
#if 1
			NSLog(@"dbl click event modifier %d", [theEvent modifierFlags]);
#endif
				{
				if([theEvent modifierFlags] & NSControlKeyMask)
					[self zoomOut:nil];
				else
					{ // move to clicked position
						[self setCenterCoordinate:MKCoordinateForMapPoint(pnt)];
						[self zoomIn:nil];
					}
				}
			return;
		}
	while(YES)
		{
		if([theEvent type] == NSLeftMouseUp)
			{
			if(speed.x || speed.y)
				{
				// if we have speed, continue to roll...
				// but we should set up a timer
				// and make the speed an iVar
				// and stop the timer if the mouse is clicked
				// speed must decrease (linearly?)
				}
			break;
			}
		if([theEvent type] == NSLeftMouseDragged)
			{ // NSMouseDragged
				NSPoint p = [self convertPoint:[theEvent locationInWindow] fromView:nil];	// initial point
				MKMapPoint p2 = [self _mapPointForPoint:p];	// where did we drag to on the Mercator map?
				pnt = [self _mapPointForPoint:p0];	// last click on Mercator map (which has been moved!)
				speed.x = pnt.x - p2.x;	// movement vector
				speed.y = pnt.y - p2.y;
				[self _moveByX:speed.x Y:speed.y];
				p0=p;	// remember screen coordinates since the mercator position changes
			}
		theEvent = [NSApp nextEventMatchingMask:(NSLeftMouseUpMask|NSLeftMouseDraggedMask)
									  untilDate:[NSDate distantFuture]						// get next event
										 inMode:NSEventTrackingRunLoopMode 
										dequeue:YES];
		}
}

@end

@implementation MKPlacemark

// for a description see http://www.icodeblog.com/2009/12/22/introduction-to-mapkit-in-iphone-os-3-0-part-2/

- (NSDictionary *) addressDictionary; { return addressDictionary; }

- (CLLocationCoordinate2D) coordinate; { return coordinate; }

- (void) setCoordinate:(CLLocationCoordinate2D) pos;
{ // checkme: does this method exist?
	coordinate=pos;
}

- (NSString *) subtitle;
{
	return @"Subtitle";	
}

- (NSString *) title;
{
	return @"Placemmark";
}

- (NSString *) thoroughfare; { return [addressDictionary objectForKey:@"Throughfare"]; }
- (NSString *) subThoroughfare; { return [addressDictionary objectForKey:@"SubThroughfare"]; }
- (NSString *) locality; { return [addressDictionary objectForKey:@"?"]; }
- (NSString *) subLocality; { return [addressDictionary objectForKey:@"?"]; }
- (NSString *) administrativeArea; { return [addressDictionary objectForKey:@"?"]; }
- (NSString *) subAdministrativeArea; { return [addressDictionary objectForKey:@"SubAdministrativeArea"]; }
- (NSString *) postalCode; { return [addressDictionary objectForKey:@"ZIP"]; }
- (NSString *) country; { return [addressDictionary objectForKey:@"Country"]; }
- (NSString *) countryCode; { return [addressDictionary objectForKey:@"CountryCode"]; }

- (id) initWithCoordinate:(CLLocationCoordinate2D) coord addressDictionary:(NSDictionary *) addr;
{
	if((self=[super init]))
		{
		coordinate=coord;
		addressDictionary=[addr retain];	// FIXME: or copy?
		}
	return self;
}

- (void) dealloc
{
	[addressDictionary release];
	[super dealloc];
}

@end

@implementation MKReverseGeocoder

- (void) cancel;
{
	if(connection)
		[connection cancel];
	[connection release];
	connection=nil;
}

- (CLLocationCoordinate2D) coordinate;
{
	return coordinate;
}

- (id <MKReverseGeocoderDelegate>) delegate;
{
	return delegate;
}

- (void) setDelegate:(id <MKReverseGeocoderDelegate>) d;
{
	delegate=d;
}

- (id) initWithCoordinate:(CLLocationCoordinate2D) coord;
{
	if((self=[super init]))
		{
		coordinate=coord;
		}
	return self;
}

- (void) dealloc
{
	[self cancel];
	[placemark release];
	[super dealloc];
}

- (BOOL) isQuerying;
{
	return connection != nil;
}

- (MKPlacemark *) placemark;
{
	return placemark;
}

- (void) start;
{
	if(!connection)
		{ // build query and start
		// use reverse geocoding api:
		//	http://developers.cloudmade.com/wiki/geocoding-http-api/Documentation#Reverse-Geocoding-httpcm-redmine01-datas3amazonawscomfiles101117091610_icon_beta_orangepng
			// read resulting property list
			// make asynchronous fetch and report result through delegate protocol
		}
}

// or should we provide a subclass "MKGeocoder" that implements initWithQuery:

- (void) _lookFor:(NSString *) query
{ // http://developers.cloudmade.com/projects/show/geocoding-http-api
	// FIXME: encode blanks as + and + as %25 etc.
	query=@"133+Fleet+street,+London,+UK";
	NSString *url=[NSString stringWithFormat:@"http://geocoding.cloudmade.com/%@/geocoding/v2/find.plist?query=%@", @"8ee2a50541944fb9bcedded5165f09d9", query];
	// we should do this asynchronously
	NSDictionary *dict=[NSDictionary dictionaryWithContentsOfURL:[NSURL URLWithString:url]];
	// convert resulting property list into a MKPlacemark
	// make asynchronous fetch and report result through delegate protocol
}

@end

