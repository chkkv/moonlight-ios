//
//  FrameStatsRecorder.m
//  Moonlight
//

#import "FrameStatsRecorder.h"

#include <os/lock.h>
#include <string.h>

@implementation FrameStatsRecorder {
    FrameSample _samples[FRAME_STATS_CAPACITY];
    NSUInteger _head;   // next write slot
    NSUInteger _count;  // valid samples, <= FRAME_STATS_CAPACITY
    os_unfair_lock _lock;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _lock = OS_UNFAIR_LOCK_INIT;
        _head = 0;
        _count = 0;
    }
    return self;
}

- (void)recordTiming:(FrameTiming)timing atTime:(double)t {
    os_unfair_lock_lock(&_lock);
    _samples[_head].t = t;
    _samples[_head].totalUs = timing.totalUs;
    _samples[_head].prepareUs = timing.prepareUs;
    _samples[_head].enqueueUs = timing.enqueueUs;
    _head = (_head + 1) % FRAME_STATS_CAPACITY;
    if (_count < FRAME_STATS_CAPACITY) {
        _count++;
    }
    os_unfair_lock_unlock(&_lock);
}

- (void)reset {
    os_unfair_lock_lock(&_lock);
    _head = 0;
    _count = 0;
    os_unfair_lock_unlock(&_lock);
}

- (NSUInteger)copySamplesInto:(FrameSample *)out maxCount:(NSUInteger)maxCount now:(double)now window:(double)window {
    if (out == NULL || maxCount == 0) {
        return 0;
    }

    double oldest = now - window;
    NSUInteger written = 0;

    os_unfair_lock_lock(&_lock);
    NSUInteger start = (_head + FRAME_STATS_CAPACITY - _count) % FRAME_STATS_CAPACITY;
    for (NSUInteger i = 0; i < _count && written < maxCount; i++) {
        const FrameSample *s = &_samples[(start + i) % FRAME_STATS_CAPACITY];
        if (s->t < oldest || s->t > now) {
            continue;
        }
        out[written++] = *s;
    }
    os_unfair_lock_unlock(&_lock);

    return written;
}

- (FrameWindowStats)statsAtTime:(double)now window:(double)window {
    FrameWindowStats stats;
    memset(&stats, 0, sizeof(stats));

    // Totals are collected for the p99 below; the other aggregates are summed
    // inline so the lock is only held for one walk over the ring.
    uint32_t totals[FRAME_STATS_CAPACITY];
    uint64_t sumTotal = 0, sumPrepare = 0, sumEnqueue = 0;
    double oldestT = 0, newestT = 0;
    NSUInteger n = 0;
    double oldest = now - window;

    os_unfair_lock_lock(&_lock);
    NSUInteger start = (_head + FRAME_STATS_CAPACITY - _count) % FRAME_STATS_CAPACITY;
    for (NSUInteger i = 0; i < _count; i++) {
        const FrameSample *s = &_samples[(start + i) % FRAME_STATS_CAPACITY];
        if (s->t < oldest || s->t > now) {
            continue;
        }
        if (n == 0) {
            oldestT = s->t;
        }
        newestT = s->t;
        totals[n] = s->totalUs;
        sumTotal += s->totalUs;
        sumPrepare += s->prepareUs;
        sumEnqueue += s->enqueueUs;
        if (s->totalUs > stats.totalMaxUs) {
            stats.totalMaxUs = s->totalUs;
        }
        n++;
    }
    os_unfair_lock_unlock(&_lock);

    stats.count = (uint32_t)n;
    if (n == 0) {
        return stats;
    }

    stats.totalAvgUs = (uint32_t)(sumTotal / n);
    stats.prepareAvgUs = (uint32_t)(sumPrepare / n);
    stats.enqueueAvgUs = (uint32_t)(sumEnqueue / n);

    // Interval based FPS: (n - 1) frame periods span oldestT..newestT. This is
    // stable at exactly the stream rate instead of flickering between N and N+1
    // like count/window would.
    stats.span = newestT - oldestT;
    if (n >= 2 && stats.span > 0.0001) {
        stats.fps = (double)(n - 1) / stats.span;
    }

    // p99 via insertion sort on a stack copy: n <= 256 and this only runs at the
    // HUD refresh rate, so it stays far below one frame budget.
    for (NSUInteger i = 1; i < n; i++) {
        uint32_t v = totals[i];
        NSInteger j = (NSInteger)i - 1;
        while (j >= 0 && totals[j] > v) {
            totals[j + 1] = totals[j];
            j--;
        }
        totals[j + 1] = v;
    }
    stats.totalP99Us = totals[(NSUInteger)((n - 1) * 0.99)];

    return stats;
}

@end
