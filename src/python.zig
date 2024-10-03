const py = @cImport({
    @cDefine("PY_SSIZE_T_CLEAN", {});
    @cInclude("/home/pedro/.conda/envs/audio_engine/include/python3.12/Python.h");
});

const std = @import("std");
const dsp = @import("dsp/dsp.zig");

// using float64 across the board
var zero: usize = 0;
//
const T: type = f64;
//

pub const std_options = .{
    .log_level = .err,
    .logFn = @import("logging.zig").logFn,
};

const log = std.log.scoped(.delia);
const fft_size: usize = 256;

var allocator_buffer: [fft_size * 20 * @sizeOf(T)]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&allocator_buffer);

fn fftDynamic(allocator: std.mem.Allocator, inlist: [*c]py.PyObject, outlist: [*c]py.PyObject, from: usize, to: usize) [*c]py.PyObject {
    if (to == from) {
        return outlist;
    }

    const fft_dynamic = dsp.transforms.FourierDynamic(T);

    const buffer = allocator.alloc(T, @as(usize, @intCast(to - from))) catch {
        py.PyErr_SetString(py.PyExc_RuntimeError, "Failed to allocate buffer memory.");
        return @as([*c]py.PyObject, (@ptrFromInt(zero)));
    };

    defer allocator.free(buffer);

    var buff_index: usize = 0;

    for (from..to) |i| {
        const item = py.PyList_GetItem(inlist, @as(py.Py_ssize_t, @intCast(i)));

        if (py.PyFloat_Check(item) == 0) {
            py.PyErr_SetString(py.PyExc_RuntimeError, "List must contain only floats.");
            return @as([*c]py.PyObject, (@ptrFromInt(zero)));
        }

        //
        buffer[buff_index] = py.PyFloat_AsDouble(item);
        buff_index += 1;
    }

    var vec = fft_dynamic.fft(allocator, buffer) catch |err| {
        errdefer allocator.free(buffer);
        log.err("Failed to perform dynamic FFT: {any}", .{err});
        py.PyErr_SetString(py.PyExc_RuntimeError, "Failed to perform FFT.");
        return @as([*c]py.PyObject, (@ptrFromInt(zero)));
    };

    defer vec.deinit(allocator);

    var vec_index: usize = 0;

    for (from..to) |i| {
        const py_complex: [*c]py.PyObject = py.PyComplex_FromDoubles(vec.get(vec_index).re, vec.get(vec_index).im);

        if (py_complex == null) {
            log.warn("Failed to create complex object.", {});
            py.Py_DECREF(outlist);
            return @as([*c]py.PyObject, (@ptrFromInt(zero)));
        }

        _ = py.PyList_SetItem(outlist, @as(py.Py_ssize_t, @intCast(i)), py_complex);
        vec_index += 1;
    }

    return outlist;
}

fn ifftDynamic(allocator: std.mem.Allocator, inlist: [*c]py.PyObject, outlist: [*c]py.PyObject, from: usize, to: usize) [*c]py.PyObject {
    const fft_dynamic = dsp.transforms.FourierDynamic(T);

    var vec = fft_dynamic.createUninitializedComplexVector(allocator, @as(usize, to - from)) catch {
        py.PyErr_SetString(py.PyExc_RuntimeError, "Failed to allocate memory for complex vector.");
        return @as([*c]py.PyObject, (@ptrFromInt(zero)));
    };

    var vec_index: usize = 0;

    for (from..to) |i| {
        const item = py.PyList_GetItem(inlist, @as(py.Py_ssize_t, @intCast(i)));

        if (py.PyComplex_Check(item) == 0) {
            py.PyErr_SetString(py.PyExc_RuntimeError, "List must contain only complex numbers.");
            return @as([*c]py.PyObject, (@ptrFromInt(zero)));
        }

        const complex = fft_dynamic.ComplexType.init(py.PyComplex_RealAsDouble(item), py.PyComplex_ImagAsDouble(item));
        vec.set(vec_index, complex);
        vec_index += 1;
    }

    vec = fft_dynamic.ifft(allocator, &vec) catch |err| {
        log.err("Failed to perform dynamic FFT: {any}", .{err});
        py.PyErr_SetString(py.PyExc_RuntimeError, "Failed to perform FFT.");
        return @as([*c]py.PyObject, (@ptrFromInt(zero)));
    };

    vec_index = 0;

    for (from..to) |i| {
        const py_complex: [*c]py.PyObject = py.PyComplex_FromDoubles(vec.get(vec_index).re, vec.get(vec_index).im);

        if (py_complex == null) {
            log.warn("Failed to create complex object.", {});
            py.Py_DECREF(outlist);
            return @as([*c]py.PyObject, (@ptrFromInt(zero)));
        }

        _ = py.PyList_SetItem(outlist, @as(py.Py_ssize_t, @intCast(i)), py_complex);
        vec_index += 1;
    }

    return outlist;
}

fn ifft(self: [*c]py.PyObject, args: [*c]py.PyObject) callconv(.C) [*c]py.PyObject {
    _ = self;

    var pylist: [*c]py.PyObject = null;

    if (py.PyArg_ParseTuple(args, "O", &pylist) == 0) {
        py.PyErr_SetString(py.PyExc_RuntimeError, "Failed to parse arguments.");
        return @as([*c]py.PyObject, (@ptrFromInt(zero)));
    }

    const pylist_size: usize = @intCast(py.PyList_Size(pylist));
    const pylist_result: [*c]py.PyObject = py.PyList_New(@as(py.Py_ssize_t, @intCast(pylist_size)));

    if (pylist_result == null) {
        py.PyErr_SetString(py.PyExc_RuntimeError, "Failed to create result list.");
        // py.Py_DECREF(pylist_result);
        return @as([*c]py.PyObject, (@ptrFromInt(zero)));
    }

    const allocator = fba.allocator();
    const fft_static = dsp.transforms.FourierStatic(T, @enumFromInt(fft_size));

    if (pylist_size < fft_size) {
        return ifftDynamic(allocator, pylist, pylist_result, 0, pylist_size);
    }

    var vec = fft_static.createUninitializedComplexVector(allocator) catch {
        py.PyErr_SetString(py.PyExc_RuntimeError, "Failed to allocate memory for complex vector.");
        return @as([*c]py.PyObject, (@ptrFromInt(zero)));
    };

    defer vec.deinit(allocator);

    var remaining: usize = pylist_size;
    var current: usize = 0;

    while (remaining > fft_size) : (remaining -= fft_size) {
        var vec_index: usize = 0;
        for (current..(current + fft_size)) |i| {
            const item: ?*py.PyObject = py.PyList_GetItem(pylist, @as(py.Py_ssize_t, @intCast(i)));

            if (py.PyComplex_Check(item) == 0) {
                py.Py_DECREF(item);
                py.PyErr_SetString(py.PyExc_RuntimeError, "List must contain only complex numbers.");
                return @as([*c]py.PyObject, (@ptrFromInt(zero)));
            }

            const complex = fft_static.ComplexType.init(py.PyComplex_RealAsDouble(item), py.PyComplex_ImagAsDouble(item));
            vec.set(vec_index, complex);
            vec_index += 1;
        }

        vec = fft_static.ifft(&vec) catch {
            log.err("static failed", .{});
            py.PyErr_SetString(py.PyExc_RuntimeError, "Failed to perform IFFT.");
            return @as([*c]py.PyObject, (@ptrFromInt(zero)));
        };

        vec_index = 0;

        for (current..(current + fft_size)) |i| {
            const py_complex: [*c]py.PyObject = py.PyComplex_FromDoubles(vec.get(vec_index).re, vec.get(vec_index).im);

            if (py_complex == null) {
                py.Py_DECREF(pylist_result);
                return @as([*c]py.PyObject, (@ptrFromInt(zero)));
            }
            _ = py.PyList_SetItem(pylist_result, @as(py.Py_ssize_t, @intCast(i)), py_complex);
        }

        current += fft_size;
    }

    return ifftDynamic(allocator, pylist, pylist_result, current, pylist_size);
}

fn fft(self: [*c]py.PyObject, args: [*c]py.PyObject) callconv(.C) [*]py.PyObject {
    _ = self;

    var pylist: ?*py.PyObject = null;
    const allocator = fba.allocator();

    if (py.PyArg_ParseTuple(args, "O", &pylist) == 0) {
        py.PyErr_SetString(py.PyExc_RuntimeError, "Failed to parse arguments.");
        return @as([*c]py.PyObject, (@ptrFromInt(zero)));
    }

    const pylist_size: usize = @intCast(py.PyList_Size(pylist));
    const pylist_result: [*c]py.PyObject = py.PyList_New(@as(py.Py_ssize_t, @intCast(pylist_size)));

    if (pylist_result == null) {
        py.PyErr_SetString(py.PyExc_RuntimeError, "Failed to create result list.");
        py.Py_DECREF(pylist_result);
        return @as([*c]py.PyObject, (@ptrFromInt(zero)));
    }

    const fft_static = dsp.transforms.FourierStatic(T, @enumFromInt(fft_size));

    if (pylist_size < fft_size) {
        return fftDynamic(allocator, pylist, pylist_result, 0, pylist_size);
    }

    var vec = fft_static.createUninitializedComplexVector(allocator) catch {
        py.PyErr_SetString(py.PyExc_RuntimeError, "Failed to allocate memory for complex vector.");
        py.Py_DECREF(pylist_result);
        return @as([*c]py.PyObject, (@ptrFromInt(zero)));
    };

    defer vec.deinit(allocator);

    var remaining: usize = pylist_size;
    var current: usize = 0;

    while (remaining > fft_size) : (remaining -= fft_size) {
        var vec_index: usize = 0;
        for (current..(current + fft_size)) |i| {
            const item = py.PyList_GetItem(pylist, @as(py.Py_ssize_t, @intCast(i)));

            if (py.PyFloat_Check(item) == 0) {
                py.Py_DECREF(pylist_result);
                py.PyErr_SetString(py.PyExc_RuntimeError, "List must contain only floats.");
                return @as([*c]py.PyObject, (@ptrFromInt(zero)));
            }

            vec.set(vec_index, fft_static.ComplexType.init(py.PyFloat_AsDouble(item), 0.0));
            vec_index += 1;
        }

        vec = fft_static.fft(&vec) catch |err| {
            log.err("Failed to perform FFT: {any}", .{err});
            py.PyErr_SetString(py.PyExc_RuntimeError, "Failed to perform FFT.");
            py.Py_DECREF(pylist_result);
            return @as([*c]py.PyObject, (@ptrFromInt(zero)));
        };

        vec_index = 0;

        for (current..(current + fft_size)) |i| {
            const py_complex: [*c]py.PyObject = py.PyComplex_FromDoubles(vec.get(vec_index).re, vec.get(vec_index).im);

            if (py_complex == null) {
                py.Py_DECREF(pylist_result);
                py.PyErr_SetString(py.PyExc_RuntimeError, "Failed to create complex object.");
                return @as([*c]py.PyObject, (@ptrFromInt(zero)));
            }

            _ = py.PyList_SetItem(pylist_result, @as(py.Py_ssize_t, @intCast(i)), py_complex);
        }

        current += fft_size;
    }

    return fftDynamic(allocator, pylist, pylist_result, current, pylist_size);
}

//fn ifft(self: [*c]py.PyObject, args: [*c]py.PyObject) callconv(.C) [*c]py.PyObject {
//    _ = self;
//
//    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//    defer if (gpa.deinit() == .leak) log.err("Memory leak detected", .{});
//
//    var pylist: [*c]py.PyObject = null;
//
//    if (py.PyArg_ParseTuple(args, "O", &pylist) == 0) {
//        py.PyErr_SetString(py.PyExc_RuntimeError, "Failed to parse arguments.");
//        return @as([*c]py.PyObject, (@ptrFromInt(zero)));
//    }
//
//    const size: py.Py_ssize_t = py.PyList_Size(pylist);
//
//    const allocator = gpa.allocator();
//    const transform = dsp.transforms.FourierDynamic(T);
//
//    var vec = transform.createUninitializedComplexVector(allocator, @as(usize, @intCast(size))) catch {
//        py.PyErr_SetString(py.PyExc_RuntimeError, "Failed to allocate memory for complex vector.");
//        return @as([*c]py.PyObject, (@ptrFromInt(zero)));
//    };
//
//    defer vec.deinit(allocator);
//
//    for (0..@as(usize, @intCast(size))) |i| {
//        const item: ?*py.PyObject = py.PyList_GetItem(pylist, @as(py.Py_ssize_t, @intCast(i)));
//
//        if (py.PyComplex_Check(item) == 0) {
//            py.Py_DECREF(item);
//            py.PyErr_SetString(py.PyExc_RuntimeError, "List must contain only complex numbers.");
//            return @as([*c]py.PyObject, (@ptrFromInt(zero)));
//        }
//
//        const complex = transform.ComplexType.init(py.PyComplex_RealAsDouble(item), py.PyComplex_ImagAsDouble(item));
//        vec.set(i, complex);
//    }
//
//    vec = transform.ifft(allocator, &vec) catch {
//        py.PyErr_SetString(py.PyExc_RuntimeError, "Failed to perform IFFT.");
//        return @as([*c]py.PyObject, (@ptrFromInt(zero)));
//    };
//
//    const complex_result: [*c]py.PyObject = py.PyList_New(@as(py.Py_ssize_t, @intCast(vec.len)));
//
//    if (complex_result == null) {
//        py.PyErr_SetString(py.PyExc_RuntimeError, "Failed to create result list.");
//        return @as([*c]py.PyObject, (@ptrFromInt(zero)));
//    }
//
//    for (0..vec.len) |i| {
//        const py_complex: [*c]py.PyObject = py.PyComplex_FromDoubles(vec.get(i).re, vec.get(i).im);
//
//        if (py_complex == null) {
//            log.warn("Failed to create complex object.", {});
//            py.Py_DECREF(complex_result);
//            continue;
//        }
//
//        _ = py.PyList_SetItem(complex_result, @as(py.Py_ssize_t, @intCast(i)), py_complex);
//    }
//
//    return complex_result;
//}

fn sineWave(self: [*c]py.PyObject, args: [*c]py.PyObject) callconv(.C) [*]py.PyObject {
    _ = self;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) log.err("Memory leak detected", .{});

    var freq: T = undefined;
    var amp: T = undefined;
    var sr: T = undefined;
    var dur: T = undefined;

    if (py.PyArg_ParseTuple(args, "dddd", &freq, &amp, &sr, &dur) == 0) {
        py.PyErr_SetString(py.PyExc_RuntimeError, "Failed to parse arguments");
        return @as([*c]py.PyObject, (@ptrFromInt(zero)));
    }

    var sineGen = dsp.waves.Sine(T).init(freq, amp, sr);
    const buf_size: usize = sineGen.bufferSizeFor(dur);

    var allocator = gpa.allocator();

    var buf = allocator.alloc(T, buf_size) catch {
        py.PyErr_SetString(py.PyExc_RuntimeError, "Failled to allocate memory");
        return @as([*c]py.PyObject, (@ptrFromInt(zero)));
    };

    defer allocator.free(buf);
    buf = sineGen.generate(buf);

    const list: [*c]py.PyObject = py.PyList_New(@as(py.Py_ssize_t, @intCast(buf_size)));

    if (list == null) {
        py.PyErr_SetString(py.PyExc_RuntimeError, "Failed to create list");
        return @as([*c]py.PyObject, (@ptrFromInt(zero)));
    }

    var i: usize = 0;

    while (i < buf_size) : (i += 1) {
        const py_float: [*c]py.PyObject = py.PyFloat_FromDouble(buf[i]);
        if (py_float == null) {
            py.Py_DECREF(list);
            py.PyErr_SetString(py.PyExc_RuntimeError, "Failed to create float object");
            return @as([*c]py.PyObject, (@ptrFromInt(zero)));
        }

        _ = py.PyList_SetItem(list, @as(isize, @intCast(i)), py_float);
    }

    return list;
}

var methods = [_]py.PyMethodDef{ py.PyMethodDef{
    .ml_name = "sine_wave",
    .ml_meth = sineWave,
    .ml_flags = py.METH_VARARGS,
    .ml_doc = "sineWave(freq, amp, sr, dur) -> List[int]\n--\n\nGenerate a sine wave of specified frequency, amplitude, sample rate, and duration.",
}, py.PyMethodDef{
    .ml_name = "fft",
    .ml_meth = fft,
    .ml_flags = py.METH_VARARGS,
    .ml_doc = "fft(data: List[float]) -> List[complex]\n--\n\nPerform a Fast Fourier Transform on the input data.",
}, py.PyMethodDef{
    .ml_name = "ifft",
    .ml_meth = ifft,
    .ml_flags = py.METH_VARARGS,
    .ml_doc = "ifft(data: List[complex]) -> List[complex]\n--\n\nPerform an Inverse Fast Fourier Transform on the input data.",
} };

var module = py.PyModuleDef{
    .m_base = py.PyModuleDef_Base{
        .ob_base = py.PyObject{
            .ob_type = null,
        },
        .m_init = null,
        .m_index = 0,
        .m_copy = null,
    },
    .m_name = "_pydelia",
    .m_doc = "Python bindings for Delia",
    .m_size = -1,
    .m_methods = &methods,
    .m_slots = null,
    .m_traverse = null,
    .m_clear = null,
    .m_free = null,
};

pub export fn PyInit__pydelia() [*]py.PyObject {
    return py.PyModule_Create(&module);
}
