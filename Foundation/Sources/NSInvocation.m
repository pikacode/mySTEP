/* 
 NSInvocation.m
 
 Object rendering of an Obj-C message (action).
 
 Copyright (C) 1998 Free Software Foundation, Inc.
 
 Author:  Andrew Kachites McCallum <mccallum@gnu.ai.mit.edu>
 Author:  Richard Frith-Macdonald <richard@brainstorm.co.uk>
 
 Author:  Nikolaus Schaller <hns@computer.org> 
 removed mframe so that we only rely on libobjc
 plus some private methods of NSMethodSignature that wrap __builtin_apply()
 (the compiler should hide and manage the processor architecture as good as possible!).
 
 Sept 2007 - should now be machine independent
 
 This file is part of the mySTEP Library and is provided
 under the terms of the GNU Library General Public License.
 
 Known Bugs:
 * it is not tested if we properly encode C-Strings etc. especially as bycopy inout...
 
 */ 

#import <Foundation/NSException.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSInvocation.h>
#import <Foundation/NSMethodSignature.h>
#import "NSPrivate.h"

@implementation NSInvocation

+ (NSInvocation *) invocationWithMethodSignature:(NSMethodSignature *)aSig
{
#if 0
	NSLog(@"NSInvocation invocationWithMethodSignature:%@ %s", aSig, [aSig _methodType]);
#endif
	return [[[NSInvocation alloc] initWithMethodSignature:aSig] autorelease];
}

- (id) init
{
	NSLog(@"don't call -init on NSInvocation");
	[self release];
	return nil;
}

- (void) setTarget:(id)anObject
{
#if 0
	NSLog(@"NSInvocation setTarget: %@", anObject);
#endif
	[self setArgument:&anObject	atIndex:0];	// handles retain/release
#if OLD
	if(_argsRetained)
		{
		[anObject retain];	// in case we do [i setTarget:[i target]]
		[[self target] release];	// release current target
		}
	[_sig _setArgument:&anObject forFrame:_argframe atIndex:0];
#endif
}

- (id) target
{
	id target=nil;	// if _sig is nil
	if(_argframe)
		[_sig _getArgument:&target fromFrame:_argframe atIndex:0];
	return target;
}

- (void) setSelector:(SEL)aSelector
{
	[_sig _setArgument:&aSelector forFrame:_argframe atIndex:1];
}

- (SEL) selector
{
	SEL selector=NULL;	// if _sig is nil
	if(_argframe)
		[_sig _getArgument:&selector fromFrame:_argframe atIndex:1];
	return selector;
}

- (BOOL) argumentsRetained					{ return _argsRetained; }
- (NSMethodSignature *) methodSignature		{ return _sig; }

- (NSString*) description
{
	id target=[self target];
	SEL sel=[self selector];
	return [NSString stringWithFormat:@"%@ %p: selector=%@ target=%@ signature=%s validReturn=%@ argsRetained=%@",
			NSStringFromClass(isa),
			self,
			NSStringFromSelector(sel),
			target==self?@"(self)":target,
			_types,
			_validReturn?@"yes":@"no",
			_argsRetained?@"yes":@"no"
			];
}

- (void) dealloc
{
#if 0
	NSLog(@"-[NSInvocation dealloc] %p", self);
	NSLog(@"-dealloc %@", self);
#endif
	if(_argsRetained && _argframe && _sig)
		[self _releaseArguments];
	if(_argframeismalloc && _argframe)
		objc_free(_argframe);	// deallocate incl. struct return buffer
	if(_retvalismalloc && _retval)
		objc_free(_retval);
	[_sig release];
	[super dealloc];
}

// Access message elements.

- (void) getArgument:(void*)buffer atIndex:(int)index
{
	if(!_argframe)
		return;
	if((unsigned)index >= _numArgs)
		[NSException raise: NSInvalidArgumentException
					format: @"bad invocation argument index (%d of %d)", index, _numArgs];
	[_sig _getArgument:buffer fromFrame:_argframe atIndex:index];
}

- (void) getReturnValue:(void *)buffer
{
	// NOTE: If the NSInvocation object has never been invoked, the result of this method is undefined.
	if(_validReturn)
		{
		[_sig _getArgument:buffer fromFrame:_retval atIndex:-1];
#if 0
		if(*_rettype == _C_ID)
			NSLog(@"getReturnValue id=%@", *(id *) buffer);
#endif		
		}
#if 1 // this is only needed if we are encoding any NSInvocation in NSPortCoder
	else
		[NSException raise: NSGenericException format: @"getReturnValue with no value set"];
#endif
}

- (void) setArgument:(void*)buffer atIndex:(int)index
{
	const char *type;
	if(!_argframe)
		return;
	if ((unsigned)index >= _numArgs)
		[NSException raise: NSInvalidArgumentException
					format: @"bad invocation argument index (%d of %d)", index, _numArgs];
	type=[_sig getArgumentTypeAtIndex:index];
	if(*type == _C_CHARPTR && _argsRetained)
		{ // free old, store a copy of new
			char *oldstr;
			char *newstr = *(char**)buffer;
			[_sig _getArgument:&oldstr fromFrame:_argframe atIndex:index];	// get previous
			if(newstr == NULL)
				[_sig _setArgument:buffer forFrame:_argframe atIndex:index];
			else
				{
				char *tmp = objc_malloc(strlen(newstr)+1);
				strcpy(tmp, newstr);
				[_sig _setArgument:tmp forFrame:_argframe atIndex:index];
				}
			if(oldstr != NULL)
				objc_free(oldstr);
		}
	else if(*type == _C_ID && _argsRetained)
		{ // release/retain
			id old=nil;
			[_sig _getArgument:&old fromFrame:_argframe atIndex:index];	// get previous
			[_sig _setArgument:buffer forFrame:_argframe atIndex:index];
			[*(id*)buffer retain];	// retain new
			[old release];	// release old
#if 0
			NSLog(@"retained arg %@", *(id*)buffer);
			NSLog(@"released arg %@", old);
#endif
		}
	else
		[_sig _setArgument:buffer forFrame:_argframe atIndex:index];
}

- (void) setReturnValue:(void*)buffer
{
#if 0
	NSLog(@"setReturnValue buffer=%08x *buffer=%08x", buffer, *(long *) buffer);
	if(*_rettype == _C_ID)
		NSLog(@"              id=%@", *(id *) buffer);
	NSLog(@"_retval=%08x", _retval);
#endif
	[_sig _setArgument:buffer forFrame:_retval atIndex:-1];
#if 0
	if(*_rettype == _C_ID)
		NSLog(@"              id=%@", *(id *) _retval);
#endif
	_validReturn = YES;
}

- (void) retainArguments
{
	int	i;
	if(_argsRetained || !_argframe)
		return;	// already retained or no need to do so
	_argsRetained = YES;
#if 0
	NSLog(@"retaining arguments %@", self);
#endif
	for(i = 0; i < _numArgs; i++)
		{
		const char *type=[_sig getArgumentTypeAtIndex:i];
		switch(*type) {
			case _C_CHARPTR: { // store a copy
				char *str=NULL;
				[_sig _getArgument:&str fromFrame:_argframe atIndex:i];
				if(str != NULL)
					{
					char *tmp = objc_malloc(strlen(str)+1);
					strcpy(tmp, str);
					[_sig _setArgument:tmp forFrame:_argframe atIndex:i];
					}
				break;
			}
			case _C_ID: { // retain object
				id obj;
				[_sig _getArgument:&obj fromFrame:_argframe atIndex:i];
#if 0
				NSLog(@"retaining arg %p", obj);
				NSLog(@"retaining arg %@", obj);
#endif
				[obj retain];
				break;
			}
			default:
				break;
		}
		}
}

- (void) invokeWithTarget:(id)anObject
{
	[_sig _setArgument:&anObject forFrame:_argframe atIndex:0];
	[self invoke];
}

- (void) invoke
{
#ifndef __APPLE__
	IMP imp;			// method implementation pointer
	id target;
	SEL selector;
	if(!_argframe)
		{
		NSLog(@"NSInvocation -invoke without argframe:%@", self);
		return;
		}
	[_sig _getArgument:&target fromFrame:_argframe atIndex:0];
#if 1
	NSLog(@"NSInvocation -invoke withTarget:%@", target);
#endif
	if(target == nil)			// A message to a nil object returns nil
		{
		memset(_retval, 0, [_sig methodReturnLength]);		// wipe out return value
		_validReturn = YES;
		return;
		}
	
	[_sig _getArgument:&selector fromFrame:_argframe atIndex:1];
	NSAssert(selector != NULL, @"you must set the selector before invoking");
	
	imp = method_get_imp(object_is_instance(target) ?
						 class_get_instance_method(((struct objc_class *) target )->class_pointer, selector)
						 : class_get_class_method(((struct objc_class *) target )->class_pointer, selector));
	
	if(imp == NULL)
		{ // If fast lookup failed, we may be forwarding or something ...
#if 0
			NSLog(@"invoke: forwarding or something ...");
#endif
			imp = objc_msg_lookup(target, selector);
		}
#if 0
	[self _log:@"stack before _call"];
	//	*((long *)1)=0;
#endif
	
	// NOTE: we run into problems if imp is itself calling forward::
	
	_validReturn=[_sig _call:imp frame:_argframe retbuf:_retval];	// call
#if 1
	[self _log:@"stack after _call"];
	//	*((long *)1)=0;
#endif
#endif
}

// FIXME: copy the debugged and tested code from -[NSPortCoder encodeInvocation:] here!

#if FIXME

/*
 * encoding of in/out/inout paramters is based on the _validReturn flag
 *
 * if validReturn, we assume we are a response and encode the result, 'out' and 'inout' paramters only
 * if no validReturn, we assume a request and encode no result, and 'in' and 'inout' parameters only
 */

- (void) encodeWithCoder:(NSCoder*) aCoder
{ // NOTE: only supports NSPortCoder
	void *buffer=objc_malloc(_maxValueLength);	// make buffer large enough for max value size
	int i;
#if 0
	[self _log:@"encodeWithCoder:"];
#endif
#if 0
	NSLog(@"buffer[%d]=%p", _maxValueLength), buffer);
#endif
	if(!buffer)
		return;
	[aCoder encodeValueOfObjCType:@encode(char *) at:&_types];
	[aCoder encodeValueOfObjCType:@encode(BOOL) at:&_validReturn];
	for(i = _validReturn?-1:0; i < _numArgs; i++)
		{ // handle all arguments (and return value)
			const char *type;
			unsigned qual=[_sig _getArgumentQualifierAtIndex:i];
			if(i >= 0)
				{ // normal argument
					type=[_sig _getArgument:buffer fromFrame:_argframe atIndex:i];
				}
			else
				{ // return value
					type=[_sig methodReturnType];
					if(*type == _C_VOID)
						continue;	// don't encode void return value
					[self getReturnValue:buffer];
				}
#if 0
			NSLog(@"NSInvocation encode arg %d qual %x type %s", i, qual, type);
#endif
			if(_validReturn && (qual & _F_IN) != 0)
				continue;	// don't encode in responses
			if(!_validReturn && (qual & _F_OUT) != 0)
				continue;	// don't encode in requests
#if 0
			NSLog(@"buffer=%p", buffer);
			NSLog(@"long buffer[0]=%x", *(long *) buffer);
#endif
			if(*type == _C_ID)
				{
				if((qual & _F_BYCOPY) != 0)
					[aCoder encodeBycopyObject:*(id *)buffer];
				else if((qual & _F_BYREF) != 0)
					[aCoder encodeByrefObject:*(id *)buffer];
				else
					[aCoder encodeObject:*(id *)buffer];
				}
			else
				[aCoder encodeValueOfObjCType:type at:buffer];	// always encode bycopy
		}
	objc_free(buffer);
}

- (id) initWithCoder:(NSCoder*)aCoder
{ // this is special behaviour: we can update an existing (otherwise initialized) NSInvocation by decoding return value and arguments
	const char *types;
	void *buffer;
	int i;
#if 0
	NSLog(@"%@ initWithCoder: %@", self, aCoder);
#endif
	[aCoder decodeValueOfObjCType:@encode(char*) at:&types];
#if 0
	NSLog(@"  decoded type=%s", types);
#endif
	[aCoder decodeValueOfObjCType:@encode(BOOL) at:&_validReturn];
#if 0
	NSLog(@"  validReturn=%@", _validReturn?@"YES":@"NO");
#endif
	if(!_sig || !_validReturn)
		{ // assume we have to decode a Request
			self=[self _initWithMethodSignature:[NSMethodSignature signatureWithObjCTypes:types] andArgFrame:NULL];
		}
	else
		{ // a response - assume we already have been initialized for _sig
#if 1
			NSLog(@"  decoded type=%s", types);
			NSLog(@"  local type=%s", _types);
#endif
			NSAssert(strcmp(types, _types) == 0, @"received different signature");		// should be the same as we have requested
		}
#if 0
	NSLog(@"  _sig=%@", _sig);
	NSLog(@"  _maxValueLength=%d", _maxValueLength);
#endif
	buffer=objc_malloc(_maxValueLength);	// make buffer large enough for max value size
	for(i = _validReturn?-1:0; i < _numArgs; i++)
		{
		unsigned qual=[_sig _getArgumentQualifierAtIndex:i];
		const char *type;
		if(i >= 0)
			{ // normal argument
				type=[_sig getArgumentTypeAtIndex:i];
			}
		else
			{ // return value
				type=_rettype;
				if(*type == _C_VOID)
					continue;	// we didn't encode a void return value
			}
#if 0
		NSLog(@"  decode arg %d type %s", i, type);
#endif
		if(_validReturn && (qual & _F_IN) != 0)
			continue;	// wasn't encoded in response
		if(!_validReturn && (qual & _F_OUT) != 0)
			continue;	// wasn't encoded in request
		[aCoder decodeValueOfObjCType:type at:buffer];
		if(i < 0)
			[self setReturnValue:buffer];
		else
			[self setArgument:buffer atIndex:i];
#if 0
		if(*type == _C_ID) NSLog(@"did set argument %d: id=%@ <%p>", i, NSStringFromClass([*(id *) buffer class]), *(id *) buffer);
		if(*type == _C_SEL) NSLog(@"did set argument %d: SEL=%@", i, NSStringFromSelector(*(SEL *) buffer));
#endif
#if 0
		[self _log:@"initWithCoder:"];
#endif
		}
	objc_free(buffer);
	return self;
}
#endif

@end  /* NSInvocation */

@implementation NSInvocation (NSUndocumented)

- (id) initWithMethodSignature:(NSMethodSignature*) aSignature
{ // undocumented in Cocoa but exists in some releases
	return [self _initWithMethodSignature:aSignature andArgFrame:NULL];
}

- (id) copyWithZone:(NSZone *) z;
{
	NIMP;
	return nil;
}

- (void) invokeSuper;
{
	NIMP;
}

- (void) _addAttachedObject:(id) obj
{
	// does this handle the Imports for DO?
	// and is this additionally encoded by the PortCoder?
	NIMP;
}

@end

@implementation NSInvocation (NSPrivate)

- (void) _releaseReturnValue;
{ // no longer needed so that we can reuse an invocation
	_validReturn=NO;	// invalidate - so that initWithCoder properly handles requests&responses
}

- (void) _releaseArguments
{
	int	i;
	if(!_argsRetained || !_argframe)
		return;	// already released or no need to do so
	_argsRetained = NO;
#if 0
	NSLog(@"releasing arguments %@", self);
#endif
	for(i = 0; i < _numArgs; i++)
		{
		const char *type=[_sig getArgumentTypeAtIndex:i];
		if(*type == _C_CHARPTR)
			{ // release the copy
				char *str;
				[_sig _getArgument:&str fromFrame:_argframe atIndex:i];
				if(str != NULL)
					objc_free(str);	// ??? immediately, or should we put it into the ARP?
			}
		else if(*type == _C_ID)
			{ // release object
				id obj;
				[_sig _getArgument:&obj fromFrame:_argframe atIndex:i];
#if 0
				NSLog(@"release arg %@", obj);
#endif
				[obj release];
			}
		}
}

- (void) _log:(NSString *) str;
{
	int i;
	id target=[self target];
	SEL selector=[self selector];
	NSLog(@"%@ %@ types=%s argframe=%p", str, /*self*/nil, _types, _argframe);
	if(!_argframe)
		return;
	for(i=0; i<18+[_sig frameLength]/4; i++)
		{ // print stack
			NSString *note=@"";
			if(&((void **)_argframe)[i] == ((void **)_argframe)[0]) note=[note stringByAppendingString:@"<<- link "];
			if(((void **)_argframe)[i] == target) note=[note stringByAppendingString:@"self "];
			if(((void **)_argframe)[i] == selector) note=[note stringByAppendingString:@"_cmd "];
			if(((void **)_argframe)[i] == (_argframe+0x28)) note=[note stringByAppendingString:@"argp "];
			if(((void **)_argframe)[i] == _argframe) note=[note stringByAppendingString:@"link ->> "];
			NSLog(@"arg[%2d]:%08x %+3d %3d %08x %12ld %@", i, &(((void **)_argframe)[i]), 4*i, ((char *)&(((void **)_argframe)[i]))-(((char **)_argframe)[0]), ((void **)_argframe)[i], ((void **)_argframe)[i], note);
		}
#if 0
	{
	void *buffer;
	NSLog(@"allocating buffer - len=%d", _maxValueLength);
	buffer=objc_malloc(_maxValueLength);	// make buffer large enough for max value size
	// print argframe
	for(i = _validReturn?-1:0; i < _numArgs; i++)
		{
		const char *type;
		unsigned qual=[_sig _getArgumentQualifierAtIndex:i];
		if(i >= 0)
			{ // normal argument
				type=[_sig _getArgument:buffer fromFrame:_argframe atIndex:i];
			}
		else
			{ // return value
				type=[_sig methodReturnType];
				[self getReturnValue:buffer];
			}
		if(*type == _C_ID)
			NSLog(@"argument %d qual=%d type=%s id=%@ <%p>", i, qual, type, NSStringFromClass([*(id *) buffer class]), *(id *) buffer);
		// NSLog(@"argument %d qual=%d type=%s %p %p", i, qual, type, *(id *) buffer, *(id *) buffer);
		else if(*type == _C_SEL)
			NSLog(@"argument %d qual=%d type=%s SEL=%@ <%p>", i, qual, type, NSStringFromSelector(*(SEL *) buffer), *(SEL *) buffer);
		else
			NSLog(@"argument %d qual=%d type=%s %08x", i, qual, type, *(long *) buffer);
		}
	objc_free(buffer);
	}
#endif
}

// this is called from NSObject/NSProxy from the forward:: method

- (id) _initWithMethodSignature:(NSMethodSignature*)aSignature andArgFrame:(arglist_t) argFrame
{
#if 0
	NSLog(@"NSInovcation _initWithMethodSignature:%@", aSignature);
#endif
	if(!aSignature)
		{ // missing signature
			[self release];
			return nil;
		}
	if((self=[super init]))
		{
		_sig = [aSignature retain];
		_argframe = [_sig _allocArgFrame:argFrame];
		if(!_argframe)
			{ // could not allocate
#if 1
				NSLog(@"_initWithMethodSignature:andArgFrame: could not allocate _argframe");
#endif
				[self release];
				return nil;
			}
		_argframeismalloc=(_argframe != argFrame);	// was re-allocated if different
		_types=[_sig _methodType];	// get method type
		_numArgs=[aSignature numberOfArguments];
		_rettype=[_sig methodReturnType];
		_returnLength=[_sig methodReturnLength];
		_maxValueLength=MAX(_returnLength, [_sig frameLength]);
		// we could use a char private[8] if _returnLength < sizeof(private)
		if(_returnLength > 0)
			{
			_retval = objc_calloc(1, _returnLength);
			if(!_retval)
				{ // could not allocate
#if 1
					NSLog(@"_initWithMethodSignature:andArgFrame: could not allocate _retval");
#endif
					[self release];
					return nil;
				}
			_retvalismalloc=YES;	// always...
			}
#if 0
		[self _log:@"_initWithMethodSignature:andArgFrame:"];
#endif
		}
	return self;
}

- (retval_t) _returnValue;
{ // encode the return value so that it can be passed back to the libobjc forward:: method
	retval_t retval;
#if 0
	NSLog(@"_returnValue called");
	[self _log:@"before getting retval"];
	if(_rettype[0] == _C_ID)
		{
		id ret;
		[self getReturnValue:&ret];
		NSLog(@"value = %@", ret);
		}
#endif
	if(_argsRetained)
		[self _releaseArguments];
	if(!_validReturn && *_rettype != _C_VOID)
		{ // no valid return value
			NSLog(@"warning - no valid return value set");
			[NSException raise: NSInvalidArgumentException format: @"did not 'setReturnValue:' for non-void NSInvocation"];
		}
	retval=[_sig _returnValue:_retval frame:_argframe];	// get return value and restore argframe if needed
#if 1
	[self _log:@"after getting retval"];
#endif
	if(!_argframeismalloc)
		_argframe=NULL;	// invalidate since it was inherited from our caller
#if 1
	NSLog(@"retval=%p %p %ul", retval, *(void **) retval, *(unsigned long *) retval);
#endif
	return retval;
}

@end

#if 0	// test

@implementation NSInvocation (Testing)

- (void) test1
{
	NSLog(@"*** test1 ***");
	NSLog(@"  self=%p", self);
	NSLog(@"  _cmd=%p", _cmd);
	NSAssert(self != nil, @"self is not set correctly; NSInvocation may be broken");	
	NSAssert(_cmd != NULL, @"_cmd is not set correctly; NSInvocation may be broken");	
}

- (void) test2:(id) arg
{
	NSLog(@"*** test2: ***");
	NSLog(@"  self=%p", self);
	NSLog(@"  _cmd=%p", _cmd);
	NSLog(@"  arg=%p", arg);
	NSAssert(self != nil, @"self is not set correctly; NSInvocation may be broken");	
	NSAssert(_cmd != NULL, @"_cmd is not set correctly; NSInvocation may be broken");	
	NSAssert(arg != nil, @"arg is not set correctly; NSInvocation may be broken");	
}

- (NSMethodSignature *) methodSignatureForSelector:(SEL)aSelector
{ // must be overridden or forwardInvocation: will not be called
	NSLog(@"methodSignatureForSelector %@ %p", NSStringFromSelector(aSelector), aSelector);
	return [NSString instanceMethodSignatureForSelector:aSelector];
}

- (void) forwardInvocation:(NSInvocation *)anInvocation
{
	id ret=nil;
	NSLog(@"NSInvocation %p forwardInvocation: %@", self, anInvocation);
	[anInvocation setReturnValue:&ret];
}

+ (void) initialize
{
	SEL sel=@selector(test2:);	// default
	NSInvocation *test=[NSInvocation invocationWithMethodSignature:[NSInvocation instanceMethodSignatureForSelector:sel]];
	NSString *str=@"teststring";
#if 0
	NSLog(@"-- NSInvocation initialize -- testing ---");
	sel=@selector(test1);
	test=[NSInvocation invocationWithMethodSignature:[NSInvocation instanceMethodSignatureForSelector:sel]];
	[test setSelector:sel];
	NSLog(@"-- test1 ---");
	[test invokeWithTarget:test];
	NSLog(@"-- test1 done ---");
	sel=@selector(test2:);
	test=[NSInvocation invocationWithMethodSignature:[NSInvocation instanceMethodSignatureForSelector:sel]];
	[test setSelector:sel];
	[test setArgument:&str atIndex:2];
	NSLog(@"-- test2 ---");
	[test invokeWithTarget:test];
	NSLog(@"-- test2 done ---");
#endif
	NSLog(@"-- test3 ---");
	NSLog(@"  self=%p", test);
	NSLog(@"  selector=%p", sel);
	NSLog(@"  object=%p", str);
	NSLog(@"  imp=%p", [NSString instanceMethodForSelector:@selector(writeToFile:atomically:encoding:error:)]);
	NSLog(@"  this=%p", [self methodForSelector:@selector(initialize)]);
	//	[test makeObjectsPerformSelector:(SEL) 0x11111111 withObject:(id) 0x22222222];	// not existing (in this class)  -> calls forward::
	[test writeToFile:(id) 0x11111111 atomically:(BOOL)0x22222222 encoding:0x33333333 error:(NSError **)0x44444444];
	
	NSLog(@"-- test3 done ---");
	NSLog(@"-- NSInvocation initialize -- done ---");
}

@end

#endif
