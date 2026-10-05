/* The one header this package translates.
 *
 * `zig build` runs translate-c over this file, and what that translation
 * becomes is the `c` module the Zig facade in zig/root.zig imports.  Its whole
 * job is to name the public headers of the library this build compiles.
 *
 * Which headers those are
 * -----------------------
 * libjpeg-turbo installs four headers (src/CMakeLists.txt:2065-2069), and this
 * file names all four:
 *
 *   jconfig.h    generated configuration: JPEG_LIB_VERSION,
 *                LIBJPEG_TURBO_VERSION, MEM_SRCDST_SUPPORTED, BITS_IN_JSAMPLE
 *                and the capability switches.  It is NOT in the source tree:
 *                src/CMakeLists.txt:716 runs
 *                `configure_file(src/jconfig.h.in jconfig.h)` and
 *                :2065 installs `${CMAKE_CURRENT_BINARY_DIR}/jconfig.h`.  It is
 *                reached here through the generated include directory that
 *                build.zig puts ahead of `src/src/` on the translation line,
 *                which is the same mechanism upstream relies on when it
 *                writes into its own binary directory.  Nothing in this file
 *                names that directory: include paths are a build-graph fact,
 *                and a macro of this build's own does not belong in a header
 *                whose job is to name upstream's headers.
 *   jmorecfg.h   manual configuration and the basic data types: JSAMPLE
 *                (:49), JCOEF (:78), JOCTET (:87), JDIMENSION (:156) and
 *                `boolean` (:204).
 *   jpeglib.h    the API.  It includes jconfig.h and jmorecfg.h itself
 *                (src/jpeglib.h:41-44), so including it in the right order
 *                also fixes the order.
 *   jerror.h     the message-code list and the ERREXIT/WARNMS/TRACEMS
 *                macros.  It is installed and documented as includable by
 *                applications ("Some applications using the JPEG library may
 *                wish to include this file to get the error codes", :17-19),
 *                so it is named here rather than left to the internal tail.
 *
 * Order matters and is not negotiable
 * -----------------------------------
 *   1. <stdio.h> and <stddef.h> first.  src/jpeglib.h:21-29 says in as many
 *      words that it does *not* include <stdio.h> "despite the fact that it
 *      uses FILE and size_t", and that calling programs are required to
 *      "include system headers that define at least the typedefs FILE and
 *      size_t" before including it.  It uses both: `FILE *outfile`
 *      (:984-985) and `size_t structsize` (:974).  This is upstream's
 *      documented requirement, not a workaround, and an installed C consumer
 *      has the same obligation.
 *   2. <jconfig.h> next, because jerror.h's message list is conditional on
 *      JPEG_LIB_VERSION (src/jerror.h:48, :55, :205, :213) and that macro is
 *      defined nowhere else.
 *   3. <jmorecfg.h>, then <jpeglib.h>, which re-includes the two above under
 *      its own guards (src/jpeglib.h:41-44).
 *   4. <jerror.h> last: its ERREXITS/ERREXIT* macros expand to
 *      `cinfo->err->msg_parm.s` and `JMSG_STR_PARM_MAX`, both of which
 *      jpeglib.h defines (:800, :792), so it has to follow jpeglib.h.
 *
 * Why jpeglib.h:1213-1214 does not pull in the private headers
 * ------------------------------------------------------------
 * The tail of jpeglib.h reads
 *
 *     #ifdef JPEG_INTERNALS
 *     #include "jpegint.h"
 *     #include "jerror.h"
 *     #endif
 *
 * (src/jpeglib.h:1212-1215), and none of it is compiled here.  JPEG_INTERNALS
 * is defined by upstream's own library modules and by nothing an application
 * defines: src/jerror.c:24 says of itself "this is not a core library module,
 * so it doesn't define JPEG_INTERNALS", and jmorecfg.h:221-223 makes
 * JPEG_INTERNALS the gate for JPEG_INTERNAL_OPTIONS, which is what guards the
 * internal capability macros.  Leaving it undefined is what makes this a
 * translation of the *public* ABI.  Under it sit jpegint.h's module structs -
 * the memory manager's private pool types, the controller and marker-writer
 * interfaces, the internal JPEG marker code - which are not installed
 * (src/CMakeLists.txt:2065-2069 installs jconfig.h, jerror.h, jmorecfg.h and
 * jpeglib.h and nothing else) and are declared in terms of types an
 * application never sees.
 *
 * jversion.h is generated and internal
 * -------------------------------------
 * src/src/jversion.h.in becomes jversion.h (src/CMakeLists.txt:631) and is
 * used by the library: src/src/jerror.c:27 includes it for JVERSION and
 * JCOPYRIGHT.  It is not installed, it declares nothing that is an entry point,
 * and a caller has no legitimate use for a two-line version string, so this
 * wrapper does not name it.  The library units still get it, because
 * build.zig puts the same generated directory on their compile line.
 *
 * What is deliberately not here
 * -----------------------------
 * A copy of any declaration, and no macro of this build's own.
 *
 * There is nothing here to configure.  The feature switches this build turns
 * off - C_ARITH_CODING_SUPPORTED, D_ARITH_CODING_SUPPORTED and WITH_SIMD
 * (src/jconfig.h.in:13, :16, :22) - are `#cmakedefine` lines that are
 * resolved when build.zig generates jconfig.h for the target being built, and
 * MEM_SRCDST_SUPPORTED (:19) is an unconditional `#define`.  Restating any of
 * them here would let the translation and the compiled library disagree about
 * the same macro, which is exactly the failure that translation/codegen split
 * exists to prevent.  See build.zig's `generateJconfig`.
 */

#ifndef LIBJPEG_TURBO_TRANSLATE_H
#define LIBJPEG_TURBO_TRANSLATE_H

/* FILE and size_t, which jpeglib.h uses and deliberately does not include:
 * src/jpeglib.h:21-29. */
#include <stddef.h>
#include <stdio.h>

/* Generated.  Reaches the generated include directory that build.zig puts
 * first on the translation line; see src/CMakeLists.txt:716 and :2065. */
#include <jconfig.h>

#include <jmorecfg.h>
#include <jpeglib.h>
#include <jerror.h>

#endif /* LIBJPEG_TURBO_TRANSLATE_H */
