# Copyright 2020 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Internal helper function that is used by the BUILD files for each
cell library workspace to set things up."""

load("@rules_hdl//dependency_support/com_google_skywater_pdk:build_defs.bzl", "skywater_cell_library", "skywater_corner")
load("@rules_hdl//dependency_support/com_google_skywater_pdk:cells_info.bzl", "sky130_cell_normalize")
load(":cell_libraries.bzl", "CELL_LIBRARIES")

def declare_cell_library(workspace_name, name, default_input_driver_cell = "", default_output_load = ""):
    """This should be called from the BUILD file of a cell library workspace. It sets up the targets for the generated files of the given library.

    Args:
      workspace_name: The name of the skywater workspace
      name: The name of the top level standard cell library
      default_input_driver_cell: Cell to assume drives primary input nets
      default_output_load: Cell to assume is being driven by each primary output
    """
    native.filegroup(
        name = "spice_models",
        srcs = native.glob(["**/*.spice"]),
        visibility = ["//visibility:public"],
    )
    library = CELL_LIBRARIES[name]
    corners = library.get("corners", {})
    all_corners = []
    for corner in corners:
        target_name = sky130_cell_normalize(name, corner).replace("sky130_fd_", "")
        corner_name = "corner-" + target_name
        all_corners.append(corner_name)

        # boolean values indicating ccsnoise and leakage information in this
        # corner.
        ccsnoise = "ccsnoise" in corners[corner]
        leakage = "leakage" in corners[corner]

        # Create the corner configuration
        skywater_corner(
            name = corner_name,
            corner = corner,
            visibility = ["//visibility:private"],
            srcs = native.glob([
                "cells/**/*.lib.json",
                "timing/*.lib.json",
            ]),
            standard_cell_name = name,
            with_ccsnoise = ccsnoise,
            with_leakage = leakage,
            standard_cell_root = "external/{}".format(workspace_name),
        )

        # Library with only just a single corner.
        skywater_cell_library(
            name = target_name,
            srcs = native.glob(
                include = [
                    "cells/**/*.lef",
                    "cells/**/*.gds",
                ],
                # There are two types of lefs in the PDK. One for magic a layout
                # tool that requires some different properties set in the LEF that
                # are not always suitable for the downstream tools like OpenROAD
                # and yosys. We're basically just choosing that we want the normal
                # lefs instead of the magic ones.
                #
                # Currently this repo doesn't integrate magic into the flow. At
                # some point it will, and we'll need to somehow have both lefs, or
                # fix the lefs upstream. Just know that you may at some point in the
                # future need to modify this.
                exclude = [
                    "cells/**/*.magic.lef",
                ],
            ),
            process_corners = [":" + corner_name],
            default_corner = corner,
            visibility = ["//visibility:public"],
            openroad_configuration = library.get("open_road_configuration", None),
            tech_lef = "tech/{}.tlef".format(name) if library.get("library_type", None) != "ip_library" else None,
            default_input_driver_cell = default_input_driver_cell,
            default_output_load = default_output_load,
        )

    # Multi-corner library
    skywater_cell_library(
        name = name,
        srcs = native.glob(
            include = [
                "cells/**/*.lef",
                "cells/**/*.gds",
            ],
            # There are two types of lefs in the PDK. One for magic a layout
            # tool that requires some different properties set in the LEF that
            # are not always suitable for the downstream tools like OpenROAD
            # and yosys. We're basically just choosing that we want the normal
            # lefs instead of the magic ones.
            #
            # Currently this repo doesn't integrate magic into the flow. At
            # some point it will, and we'll need to somehow have both lefs, or
            # fix the lefs upstream. Just know that you may at some point in the
            # future need to modify this.
            exclude = [
                "cells/**/*.magic.lef",
            ],
        ),
        process_corners = [":{}".format(corner) for corner in all_corners],
        default_corner = library.get("default_corner", ""),
        visibility = ["//visibility:public"],
        openroad_configuration = library.get("open_road_configuration", None),
        tech_lef = "tech/{}.tlef".format(name) if library.get("library_type", None) != "ip_library" else None,
        default_input_driver_cell = default_input_driver_cell,
        default_output_load = default_output_load,
    )
