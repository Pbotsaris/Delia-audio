/*
 * Free FFT and convolution (C)
 *
 * Copyright (c) 2021 Project Nayuki. (MIT License)
 * https://www.nayuki.io/page/free-small-fft-in-multiple-languages
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * - The above copyright notice and this permission notice shall be included in
 *   all copies or substantial portions of the Software.
 * - The Software is provided "as is", without warranty of any kind, express or
 *   implied, including but not limited to the warranties of merchantability,
 *   fitness for a particular purpose and noninfringement. In no event shall the
 *   authors or copyright holders be liable for any claim, damages or other
 *   liability, whether in an action of contract, tort or otherwise, arising
 * from, out of or in connection with the Software or the use or other dealings
 * in the Software.
 */



// before
//❯ zig build test --summary all
//test
//└─ run test stderr
//fft: 0.00
//dft: 0.00
//-
//fft: 0.89
//dft: 1.12
//-
//fft: -1.32
//dft: 1.12
//-
//fft: 1.97
//dft: 1.13
//-
//fft: -0.44
//dft: 1.13
//-
//fft: 0.94
//dft: 1.12
//-
//fft: 1.54
//dft: 1.13
//-
//fft: -0.30
//dft: 1.13
//-
//fft: -0.00
//dft: 1.13
//-
//
//-----------------
//fft inversed: 0.36, 0.44
//dft inversed: 1.00, -0.00
//-
//fft inversed: 0.21, 0.43
//dft inversed: -1.00, 0.00
//-
//fft inversed: 0.54, -0.37
//dft inversed: -0.79, 0.25
//-
//fft inversed: -0.31, 0.21
//dft inversed: 0.32, -0.09
//-
//fft inversed: -0.11, -0.44
//dft inversed: -0.65, 0.10
//-
//fft inversed: 0.41, -0.36
//dft inversed: -0.39, -0.55
//-
//fft inversed: 0.39, -0.27
//dft inversed: 0.03, -0.32
//-
//fft inversed: -0.15, 0.19
//dft inversed: 0.50, -0.43
//-
//fft inversed: -0.27, -0.15
//dft inversed: -0.19, 0.16


// before change
//❯ zig build test --summary all
//test
//└─ run test stderr
//inversed: 0.36425954, 0.4415535
//inversed: 0.20938939, 0.42893967
//inversed: 0.53853136, -0.37483793
//inversed: -0.3122076, 0.20644407
//inversed: -0.11402022, -0.44126818
//inversed: 0.40850547, -0.36458954
//inversed: 0.38600132, -0.26634905
//inversed: -0.1451025, 0.18617548
//inversed: -0.26949632, -0.14777523
//
// After changing
//❯ zig build test --summary all
//test
//└─ run test stderr
//inversed: 0.36425954, 0.4415535
//inversed: 0.20938939, 0.42893967
//inversed: 0.53853136, -0.37483793
//inversed: -0.3122076, 0.20644407
//inversed: -0.11402022, -0.44126818
//inversed: 0.40850547, -0.36458954
//inversed: 0.38600132, -0.26634905
//inversed: -0.1451025, 0.18617548
//inversed: -0.26949632, -0.14777523
//Build Summary: 3/3 steps succeeded; 29/29 tests passed
//test success
//└─ run test 29 passed 3ms MaxRSS:5M
//   └─ zig test Debug native success 1s MaxRSS:311M
//
//

#include "fft.h"
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// Private function prototypes
static size_t reverse_bits(size_t val, int width);
static void *memdup(const void *src, size_t n);

bool Fft_transform(double complex vec[], size_t n, bool inverse) {
  if (n == 0)
    return true;
  else if ((n & (n - 1)) == 0) // Is power of 2
    return Fft_transformRadix2(vec, n, inverse);
  else // More complicated algorithm for arbitrary sizes
    return Fft_transformBluestein(vec, n, inverse);
}

bool Fft_transformRadix2(double complex vec[], size_t n, bool inverse) {
  // Length variables
  int levels = 0; // Compute levels = floor(log2(n))
                  //
  for (size_t temp = n; temp > 1U; temp >>= 1)
    levels++;

  if ((size_t)1U << levels != n)
    return false; // n is not a power of 2

  // Trigonometric tables
  if (SIZE_MAX / sizeof(double complex) < n / 2)
    return false;

  double complex *exptable = malloc((n / 2) * sizeof(double complex));

  if (exptable == NULL)
    return false;

  for (size_t i = 0; i < n / 2; i++)
    exptable[i] = cexp((inverse ? 2 : -2) * M_PI * i / n * I);

  // Bit-reversed addressing permutation
  for (size_t i = 0; i < n; i++) {
    size_t j = reverse_bits(i, levels);
    if (j > i) {
      double complex temp = vec[i];
      vec[i] = vec[j];
      vec[j] = temp;
    }
  }

  // Cooley-Tukey decimation-in-time radix-2 FFT
  for (size_t size = 2; size <= n; size *= 2) {
    size_t halfsize = size / 2;
    size_t tablestep = n / size;
    for (size_t i = 0; i < n; i += size) {
      for (size_t j = i, k = 0; j < i + halfsize; j++, k += tablestep) {
        size_t l = j + halfsize;
        double complex temp = vec[l] * exptable[k];
        vec[l] = vec[j] - temp;
        vec[j] += temp;
      }
    }
    if (size == n) // Prevent overflow in 'size *= 2'
      break;
  }

  free(exptable);
  return true;
}

bool Fft_transformBluestein(double complex vec[], size_t n, bool inverse) {
  bool status = false;

  // Find a power-of-2 convolution length m such that m >= n * 2 + 1
  size_t m = 1;
  while (m / 2 <= n) {
    if (m > SIZE_MAX / 2)
      return false;
    m *= 2;
  }

  // Allocate memory
  if (SIZE_MAX / sizeof(double complex) < n ||
      SIZE_MAX / sizeof(double complex) < m)
    return false;

  double complex *exptable = malloc(n * sizeof(double complex));
  double complex *avec = calloc(m, sizeof(double complex));
  double complex *bvec = calloc(m, sizeof(double complex));
  double complex *cvec = malloc(m * sizeof(double complex));
  if (exptable == NULL || avec == NULL || bvec == NULL || cvec == NULL)
    goto cleanup;

  // Trigonometric tables
  for (size_t i = 0; i < n; i++) {
    uintmax_t temp = ((uintmax_t)i * i) % ((uintmax_t)n * 2);
    double angle = (inverse ? M_PI : -M_PI) * temp / n;
    exptable[i] = cexp(angle * I);
  }

  // Temporary vectors and preprocessing
  for (size_t i = 0; i < n; i++)
    avec[i] = vec[i] * exptable[i];

  bvec[0] = exptable[0];
  for (size_t i = 1; i < n; i++)
    bvec[i] = bvec[m - i] = conj(exptable[i]);

  // Convolution
  if (!Fft_convolve(avec, bvec, cvec, m))
    goto cleanup;

  // Postprocessing
  for (size_t i = 0; i < n; i++)
    vec[i] = cvec[i] * exptable[i];
  status = true;

  // Deallocation
cleanup:
  free(exptable);
  free(avec);
  free(bvec);
  free(cvec);
  return status;
}

bool Fft_convolve(const double complex xvec[restrict],
                  const double complex yvec[restrict],
                  double complex outvec[restrict],
                  size_t n) {

  bool status = false;

  if (SIZE_MAX / sizeof(double complex) < n) return false;
  double complex *xv = memdup(xvec, n * sizeof(double complex));

  double complex *yv = memdup(yvec, n * sizeof(double complex));

  if (xv == NULL || yv == NULL) goto cleanup;

  if (!Fft_transform(xv, n, false)) goto cleanup;
  if (!Fft_transform(yv, n, false)) goto cleanup;

  for (size_t i = 0; i < n; i++) xv[i] *= yv[i];

  if (!Fft_transform(xv, n, true)) goto cleanup;

  for (size_t i = 0; i < n; i++) // Scaling (because this FFT implementation omits it)
    outvec[i] = xv[i] / n;

  status = true;

cleanup:
  free(xv);
  free(yv);
  return status;
}

static size_t reverse_bits(size_t val, int width) {
  size_t result = 0;
  for (int i = 0; i < width; i++, val >>= 1)
    result = (result << 1) | (val & 1U);
  return result;
}

static void *memdup(const void *src, size_t n) {
  void *dest = malloc(n);
  if (n > 0 && dest != NULL)
    memcpy(dest, src, n);
  return dest;
}



bool Fft_transformBluestein2(double complex vec[], size_t n, bool inverse) {
  bool status = false;

  size_t m = 1;
  while (m / 2 <= n) {
    if (m > SIZE_MAX / 2)
      return false;
    m *= 2;
  }

  if (SIZE_MAX / sizeof(double complex) < n ||
      SIZE_MAX / sizeof(double complex) < m)
    return false;

  double complex *exptable = malloc(n * sizeof(double complex));

  // we allocate them here. if this function is called again by recursive calls, then a new allocation will be done, correct?
  double complex *avec = calloc(m, sizeof(double complex));
  double complex *bvec = calloc(m, sizeof(double complex));

  double complex *cvec = malloc(m * sizeof(double complex));
  if (exptable == NULL || avec == NULL || bvec == NULL || cvec == NULL)
    goto cleanup;

  for (size_t i = 0; i < n; i++) {
    uintmax_t temp = ((uintmax_t)i * i) % ((uintmax_t)n * 2);
    double angle = (inverse ? M_PI : -M_PI) * temp / n;
    exptable[i] = cexp(angle * I);
  }

  // here we modify the avec and bvec but this is before convolution where the duplication happens
  for (size_t i = 0; i < n; i++)
    avec[i] = vec[i] * exptable[i];
  bvec[0] = exptable[0];
  for (size_t i = 1; i < n; i++)
    bvec[i] = bvec[m - i] = conj(exptable[i]);

  /// now we convolve. If there is no duplication, avec and bvec will be modiefied
  if (!Fft_convolve(avec, bvec, cvec, m))
    goto cleanup;

  // finally, the postprocessing which is done only with the cvec, output vector and the exp table.
  //  we do not use avec and bvec here at all
  //  the output vector is vec
  for (size_t i = 0; i < n; i++)
    vec[i] = cvec[i] * exptable[i];
  status = true;

  // Deallocation
cleanup:
  free(exptable);
  free(avec);
  free(bvec);
  free(cvec);
  return status;
}

