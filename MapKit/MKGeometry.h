//
//  MKGeometry.h
//  MapKit
//
//  Created by H. Nikolaus Schaller on 04.10.10.
//  Copyright 2009 Golden Delicious Computers GmbH&Co. KG. All rights reserved.
//
//  for understanding the coordinate systems
//  see http://developer.apple.com/library/ios/#documentation/UserExperience/Conceptual/LocationAwarenessPG/MapKit/MapKit.html
//  and http://troybrant.net/blog/2010/01/mkmapview-and-zoom-levels-a-visual-guide/

#ifndef Include_MKGeometry
#define Include_MKGeometry

#import <Cocoa/Cocoa.h>
#import <CoreLocation/CoreLocation.h>

#if !TARGET_OS_IPHONE
#define CGRectEdge NSRectEdge
#endif

typedef struct _MKCoordinateSpan
{
	CLLocationDegrees latitudeDelta;
	CLLocationDegrees longitudeDelta;
} MKCoordinateSpan;

typedef struct _MKCoordinateRegion
{
	CLLocationCoordinate2D center;
	MKCoordinateSpan span;
} MKCoordinateRegion;

typedef struct _MKMapPoint	// Mercator point corresponding to some lat/long point (CLLocationCoordinate2D) - NOTE: there is no defined scale
{
	double x;
	double y;
} MKMapPoint;

typedef struct _MKMapSize	// size on a Mercator map
{
	double width;
	double height;
} MKMapSize;

typedef struct _MKMapRect	// area on the Mercator map
{
	MKMapPoint origin;
	MKMapSize size;
} MKMapRect;

typedef CGFloat MKZoomScale;

CLLocationCoordinate2D MKCoordinateForMapPoint(MKMapPoint mapPoint);
MKCoordinateRegion MKCoordinateRegionForMapRect(MKMapRect rect);
static inline MKCoordinateRegion MKCoordinateRegionMake(CLLocationCoordinate2D center, MKCoordinateSpan span)
{
	return (MKCoordinateRegion) { center, span };
}
MKCoordinateRegion MKCoordinateRegionMakeWithDistance(CLLocationCoordinate2D center,
													  CLLocationDistance lat,
													  CLLocationDistance lng);
static inline MKCoordinateSpan MKCoordinateSpanMake(CLLocationDegrees lat, CLLocationDegrees lng)
{
	return (MKCoordinateSpan) { lat, lng };
}
BOOL MKMapPointEqualToPoint(MKMapPoint p1, MKMapPoint p2);
MKMapPoint MKMapPointForCoordinate(CLLocationCoordinate2D coord);
MKMapPoint MKMapPointMake(double x, double y);
double MKMapPointsPerMeterAtLatitude(CLLocationDegrees lat);
BOOL MKMapRectContainsPoint(MKMapRect rect, MKMapPoint point);
BOOL MKMapRectContainsRect(MKMapRect r1, MKMapRect r2);
void MKMapRectDivide(MKMapRect rect, MKMapRect *slice, MKMapRect *remainder, double amount, CGRectEdge edge);
BOOL MKMapRectEqualToRect(MKMapRect r1, MKMapRect r2);
double MKMapRectGetHeight(MKMapRect rect);
double MKMapRectGetMaxX(MKMapRect rect);
double MKMapRectGetMaxY(MKMapRect rect);
double MKMapRectGetMidX(MKMapRect rect);
double MKMapRectGetMidY(MKMapRect rect);
double MKMapRectGetMinX(MKMapRect rect);
double MKMapRectGetMinY(MKMapRect rect);
double MKMapRectGetWidth(MKMapRect rect);
MKMapRect MKMapRectInset(MKMapRect rect, double dx, double dy);
MKMapRect MKMapRectIntersection(MKMapRect r1, MKMapRect r2);
BOOL MKMapRectIntersectsRect(MKMapRect r1, MKMapRect r2);
BOOL MKMapRectIsEmpty(MKMapRect rect);
BOOL MKMapRectIsNull(MKMapRect rect);
MKMapRect MKMapRectMake(double x, double y, double w, double h);
MKMapRect MKMapRectOffset(MKMapRect rect, double dx, double dy);
MKMapRect MKMapRectRemainder(MKMapRect rect);
BOOL MKMapRectSpans180thMeridian(MKMapRect rect);
MKMapRect MKMapRectUnion(MKMapRect r1, MKMapRect r2);
BOOL MKMapSizeEqualToSize(MKMapSize r1, MKMapSize r2);
MKMapSize MKMapSizeMake(double w, double h);
CLLocationDistance MKMetersBetweenMapPoints(MKMapPoint a, MKMapPoint b);
CLLocationDistance MKMetersPerMapPointAtLatitude(CLLocationDegrees lat);
NSString *MKStringFromMapPoint(MKMapPoint point);
NSString *MKStringFromMapRect(MKMapRect rect);
NSString *MKStringFromMapSize(MKMapSize size);

#endif
// EOF
