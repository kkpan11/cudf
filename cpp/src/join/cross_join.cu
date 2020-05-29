/*
 * Copyright (c) 2020, NVIDIA CORPORATION.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include <cudf/column/column.hpp>
#include <cudf/copying.hpp>
#include <cudf/detail/nvtx/ranges.hpp>
#include <cudf/detail/repeat.hpp>
#include <cudf/filling.hpp>
#include <cudf/join.hpp>
#include <cudf/reshape.hpp>
#include <cudf/table/table.hpp>
#include <cudf/table/table_view.hpp>
#include <cudf/types.hpp>
#include <cudf/utilities/error.hpp>

namespace cudf {
namespace detail {
/**
 * @brief  Performs a cross join on two tables (left, right)
 *
 * The cross join returns the cartesian product of rows from each table.
 *
 * The approach is to repeat the left table by the number of rows in the right table
 * and tile the right table by the number of rows in the left table.
 *
 * @throws cudf::logic_error if number of columns in either `left` or `right` table is 0
 *
 * @param[in] left                  The left table
 * @param[in] right                 The right table
 * @param[in] mr                    Device memory resource to use for device memory allocation
 * @param[in] stream                Cuda stream
 *
 * @returns                         Result of cross joining `left` and `right` tables
 */
std::unique_ptr<cudf::table> cross_join(
  cudf::table_view const& left,
  cudf::table_view const& right,
  rmm::mr::device_memory_resource* mr = rmm::mr::get_default_resource(),
  cudaStream_t stream                 = 0)
{
  CUDF_EXPECTS(0 != left.num_columns(), "Left table is empty");
  CUDF_EXPECTS(0 != right.num_columns(), "Right table is empty");

  // If left or right table has no rows, return an empty table with all columns
  if ((0 == left.num_rows()) || (0 == right.num_rows())) {
    auto empty_left_columns{empty_like(left)->release()};
    auto empty_right_columns{empty_like(right)->release()};
    std::move(empty_right_columns.begin(),
              empty_right_columns.end(),
              std::back_inserter(empty_left_columns));
    return std::make_unique<table>(std::move(empty_left_columns));
  }

  // Repeat left table
  numeric_scalar<size_type> num_repeats{right.num_rows()};
  auto left_repeated{detail::repeat(left, num_repeats, mr, stream)};

  // Tile right table
  auto right_tiled{cudf::tile(right, left.num_rows(), mr)};

  // Concatenate all repeated/tiled columns into one table
  auto left_repeated_columns{left_repeated->release()};
  auto right_tiled_columns{right_tiled->release()};
  std::move(right_tiled_columns.begin(),
            right_tiled_columns.end(),
            std::back_inserter(left_repeated_columns));

  return std::make_unique<table>(std::move(left_repeated_columns));
}
}  // namespace detail

std::unique_ptr<cudf::table> cross_join(cudf::table_view const& left,
                                        cudf::table_view const& right,
                                        rmm::mr::device_memory_resource* mr)
{
  CUDF_FUNC_RANGE();
  return detail::cross_join(left, right, mr, 0);
}

}  // namespace cudf
