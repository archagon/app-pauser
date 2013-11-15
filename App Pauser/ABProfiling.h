//
//  ABProfiling.h
//  App Pauser
//
//  Created by Alexei Baboulevitch on 11/14/13.
//  Copyright (c) 2013 Alexei Baboulevitch. All rights reserved.
//

#define ABTIME_START(x)             double startTime##x = CACurrentMediaTime();                                         \

#define ABTIME_END(x, print)        double endTime##x = CACurrentMediaTime();                                           \
                                    (print ? NSLog(@"Time for %s: %f", #x, (endTime##x - startTime##x)) : 0);           \

#define ABTIME_AVG_START(x)         static double totalTime##x = 0;                                                     \
                                    static unsigned int totalTimes##x = 0;                                              \
                                    double startTime##x = CACurrentMediaTime();                                         \

#define ABTIME_AVG_END(x, printEvery, print)     double endTime##x = CACurrentMediaTime();                                          \
                                                if (totalTimes##x == 0)                                                             \
                                                {                                                                                   \
                                                    totalTime##x = endTime##x - startTime##x;                                       \
                                                }                                                                                   \
                                                else                                                                                \
                                                {                                                                                   \
                                                    totalTime##x += (endTime##x - startTime##x) / (totalTimes##x + 1);              \
                                                    totalTime##x *= (totalTimes##x + 1) / ((NSTimeInterval)totalTimes##x + 2);      \
                                                }                                                                                   \
                                                totalTimes##x++;                                                                    \
                                                (print && !(totalTimes##x % printEvery) ? NSLog(@"Average time for %s: %f", #x, totalTime##x) : 0);