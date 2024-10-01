const py = @cImport({
    @cDefine("PY_SSIZE_T_CLEAN", {});
    @cInclude("/home/pedro/.conda/envs/audio_engine/include/python3.12/Python.h");
});

const std = @import("std");
const dsp = @import("dsp/dsp.zig");

// using float64 across the board
var zero: usize = 0;
const T: type = f64;

pub const std_options = .{
    .log_level = .err,
    .logFn = @import("logging.zig").logFn,
};

const log = std.log.scoped(.delia);

const print = std.debug.print;

// for the python interop, performance is not critical so we use the more
// convient fft with dynamic allocation
fn fft(self: [*c]py.PyObject, args: [*c]py.PyObject) callconv(.C) [*]py.PyObject {
    _ = self;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) log.err("Memory leak detected", .{});

    var pylist: ?*py.PyObject = null;

    if (py.PyArg_ParseTuple(args, "O", &pylist) == 0) {
        py.PyErr_SetString(py.PyExc_RuntimeError, "Failed to parse arguments.");
        return @as([*c]py.PyObject, (@ptrFromInt(zero)));
    }

    const size: py.Py_ssize_t = py.PyList_Size(pylist);

    const allocator = gpa.allocator();
    var buffer = allocator.alloc(T, @as(usize, @intCast(size))) catch {
        py.PyErr_SetString(py.PyExc_RuntimeError, "Failed to allocate buffer memory.");
        return @as([*c]py.PyObject, (@ptrFromInt(zero)));
    };

    defer allocator.free(buffer);

    for (0..@as(usize, @intCast(size))) |i| {
        const item = py.PyList_GetItem(pylist, @as(py.Py_ssize_t, @intCast(i)));

        if (py.PyFloat_Check(item) == 0) {
            py.PyErr_SetString(py.PyExc_RuntimeError, "List must contain only floats.");
            return @as([*c]py.PyObject, (@ptrFromInt(zero)));
        }

        buffer[i] = py.PyFloat_AsDouble(item);
    }

    const transform = dsp.transforms.FourierDynamic(T);

    var vec = transform.fft(allocator, buffer) catch {
        errdefer allocator.free(buffer);

        py.PyErr_SetString(py.PyExc_RuntimeError, "Failed to perform FFT.");
        return @as([*c]py.PyObject, (@ptrFromInt(zero)));
    };

    defer vec.deinit(allocator);

    const complex_result: [*c]py.PyObject = py.PyList_New(@as(py.Py_ssize_t, @intCast(vec.len)));

    if (complex_result == null) {
        py.PyErr_SetString(py.PyExc_RuntimeError, "Failed to create result list.");
        return @as([*c]py.PyObject, (@ptrFromInt(zero)));
    }

    for (0..vec.len) |i| {
        const py_complex: [*c]py.PyObject = py.PyComplex_FromDoubles(vec.get(i).re, vec.get(i).im);

        if (py_complex == null) {
            log.warn("Failed to create complex object.", {});
            py.Py_DECREF(complex_result);
            continue;
        }

        _ = py.PyList_Append(complex_result, py_complex);
    }

    return complex_result;
}

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
