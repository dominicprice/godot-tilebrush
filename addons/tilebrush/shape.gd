@tool
extends Object

class_name TileBrushShape

enum PixelValue {
	Empty = 0,
	Border = 1 << 0,
	Fill = 1 << 1,
	Placeholder = 1 << 2,
	All = 0xff,
}


class Shape:
	var size: Vector2i
	var data: PackedInt32Array
	var points: Array[Vector2i]
	var dirty: bool


	func _init(size: Vector2i) -> void:
		self.size = size
		self.data = []
		self.data.resize(size.x * size.y)
		self.data.fill(PixelValue.Empty)
		self.points = []
		self.dirty = false


	static func rectangle(size: Vector2i, corner_radius: int = 0) -> Shape:
		if corner_radius * 2 >= size.y:
			corner_radius = floori(size.y / 2)
		if corner_radius * 2 >= size.x:
			corner_radius = floori(size.x / 2)

		var shape: Shape = Shape.new(size)

		# fill in top and bottom rows
		for x in range(corner_radius, size.x - corner_radius):
			shape.set_cell(x, 0, PixelValue.Border)
			shape.set_cell(x, size.y - 1, PixelValue.Border)

		# fill in left and right columns
		for y in range(corner_radius, size.y - corner_radius):
			shape.set_cell(0, y, PixelValue.Border)
			shape.set_cell(size.x - 1, y, PixelValue.Border)

		# make a circle and copy the corners from it
		var corner: Shape = Shape.ellipse(
			Vector2i(
				corner_radius * 2 + 1,
				corner_radius * 2 + 1,
			),
		)
		for x in range(corner_radius):
			for y in range(corner_radius):
				shape.set_cell(x, y, corner.get_cell(x, y))
				shape.set_cell(x, size.y - corner_radius + y, corner.get_cell(x, corner_radius - y - 1))
				shape.set_cell(size.x - corner_radius + x, y, corner.get_cell(corner_radius - x - 1, y))
				shape.set_cell(size.x - corner_radius + x, size.y - corner_radius + y, corner.get_cell(corner_radius - x - 1, corner_radius - y - 1))

		return shape


	static func ellipse(size: Vector2i) -> Shape:
		var shape: Shape = Shape.new(size)

		# the algorithm doesn't handle small ellipses well, so we
		# program them manually
		if size.x <= 2 or size.y <= 2:
			# for these very small shapes, the best approximation is a
			# rectangle
			shape.replace(PixelValue.Border, PixelValue.Empty)
		elif size.x <= 4 or size.y <= 4:
			# for these slightly bigger but still small shapes, we still
			# do a rectangle but cut off the corner tiles
			for x in range(1, size.x - 1):
				shape.set_cell(x, 0, PixelValue.Border)
				shape.set_cell(x, size.y - 1, PixelValue.Border)
			for y in range(1, size.y - 1):
				shape.set_cell(0, y, PixelValue.Border)
				shape.set_cell(size.x - 1, y, PixelValue.Border)
			return shape

		# calculate radius in both directions; if either dimension is
		# even then the algorithm won't work and the radius will be
		# too big to fit inside the shape, so we subtract one from it
		# now and we will later stretch out the shape by one tile
		var rx: int = size.x / 2
		if size.x % 2 == 0:
			rx -= 1
		var ry: int = size.y / 2
		if size.y % 2 == 0:
			ry -= 1
		var x: int = 0
		var y: int = ry
		var rx2 := rx * rx
		var ry2 := ry * ry
		var dx := 0
		var dy := 2 * rx2 * y

		var p1 := ry2 - rx2 * ry + rx2 / 4
		while dx < dy:
			shape.set_cell(rx + x, ry + y, PixelValue.Border)
			shape.set_cell(rx - x, ry + y, PixelValue.Border)
			shape.set_cell(rx + x, ry - y, PixelValue.Border)
			shape.set_cell(rx - x, ry - y, PixelValue.Border)

			x += 1
			dx += 2 * ry2
			if p1 < 0:
				p1 += ry2 + dx
			else:
				y -= 1
				dy -= 2 * rx2
				p1 += ry2 + dx - dy

		var p2 = ry2 * x * x + rx2 * (y - 1) * (y - 1) - rx2 * ry2
		while y >= 0:
			shape.set_cell(rx + x, ry + y, PixelValue.Border)
			shape.set_cell(rx - x, ry + y, PixelValue.Border)
			shape.set_cell(rx + x, ry - y, PixelValue.Border)
			shape.set_cell(rx - x, ry - y, PixelValue.Border)

			y -= 1
			dy -= 2 * rx2
			if p2 > 0:
				p2 += rx2 - dy
			else:
				x += 1
				dx += 2 * ry2
				p2 += rx2 - dy + dx

		# we now stretch out by one tile right/down if that dimension was even
		if size.x % 2 == 0:
			for vx in range(size.x - 1, rx, -1):
				for vy in range(size.y):
					shape.set_cell(vx, vy, shape.get_cell(vx - 1, vy))
					shape.set_cell(vx - 1, vy, PixelValue.Empty)
		if size.y % 2 == 0:
			for vy in range(size.y - 1, ry, -1):
				for vx in range(size.x):
					shape.set_cell(vx, vy, shape.get_cell(vx, vy - 1))
					shape.set_cell(vx, vy - 1, PixelValue.Empty)

		# we now fill in the gaps we made
		shape.set_cell(rx, 0, PixelValue.Border)
		shape.set_cell(rx, size.y - 1, PixelValue.Border)
		shape.set_cell(0, ry, PixelValue.Border)
		shape.set_cell(size.x - 1, ry, PixelValue.Border)

		return shape


	static func diamond(size: Vector2i) -> Shape:
		var shape := Shape.new(size)

		var cx := size.x / 2
		var cy := size.y / 2

		# Vertices
		var top = Vector2i(cx, 0)
		var right = Vector2i(size.x - 1, cy)
		var bottom = Vector2i(cx, size.y - 1)
		var left = Vector2i(0, cy)

		shape.draw_line(top, right)
		shape.draw_line(right, bottom)
		shape.draw_line(bottom, left)
		shape.draw_line(left, top)

		return shape


	static func cross(size: Vector2i, hbeam: int, vbeam) -> Shape:
		var shape: Shape = Shape.new(size)
		var x0: int = floori(size.x - hbeam) / 2
		var x1: int = ceili(size.x + hbeam) / 2
		var y0: int = floori(size.y - vbeam) / 2
		var y1: int = ceili(size.y + vbeam) / 2

		# top and bottom
		for x in range(x0, x1 + 1):
			shape.set_cell(x, 0, PixelValue.Border)
			shape.set_cell(x, size.y - 1, PixelValue.Border)
		# left and right
		for y in range(y0, y1 + 1):
			shape.set_cell(0, y, PixelValue.Border)
			shape.set_cell(size.x - 1, y, PixelValue.Border)
		# left legs
		for x in range(1, x0 + 1):
			shape.set_cell(x, y0, PixelValue.Border)
			shape.set_cell(x, y1, PixelValue.Border)
		# right legs
		for x in range(x1, size.x - 1):
			shape.set_cell(x, y0, PixelValue.Border)
			shape.set_cell(x, y1, PixelValue.Border)
		# top legs
		for y in range(1, y0):
			shape.set_cell(x0, y, PixelValue.Border)
			shape.set_cell(x1, y, PixelValue.Border)
		# bottom legs
		for y in range(y1 + 1, size.y - 1):
			shape.set_cell(x0, y, PixelValue.Border)
			shape.set_cell(x1, y, PixelValue.Border)
		return shape


	func draw_line(start: Vector2i, end: Vector2i, v: PixelValue = PixelValue.Border) -> void:
		var dx = abs(end.x - start.x)
		var dy = -abs(end.y - start.y)
		var sx = 1 if start.x < end.x else -1
		var sy = 1 if start.y < end.y else -1
		var err = dx + dy

		self.set_cell(start.x, start.y, v)
		while start != end:
			var e2 = 2 * err
			if e2 >= dy:
				err += dy
				start.x += sx
			if e2 <= dx:
				err += dx
				start.y += sy
			self.set_cell(start.x, start.y, v)


	func combine(shape: Shape) -> void:
		if shape.w != self.size.x or shape.h != self.size.y:
			printerr("cannot combine shapes of different sizes")
		for x in range(self.size.x):
			for y in range(self.size.y):
				if shape.get_cell(x, y) == PixelValue.Border:
					self.set_cell(x, y, PixelValue.Border)


	# return an array of points in the shape
	func to_array(offset: Vector2i) -> Array[Vector2i]:
		if dirty:
			# recompute the points
			self.points = []
			for y in range(self.size.y):
				for x in range(self.size.x):
					var v: PixelValue = self.get_cell(x, y)
					if v != PixelValue.Empty:
						self.points.append(Vector2i(x, y))
			dirty = false

		# we need the offset to be the middle of the shape, so increase
		# it by (w, h) / 2
		offset.x -= roundi(self.size.x / 2)
		offset.y -= roundi(self.size.y / 2)
		var res: Array[Vector2i] = []
		for point in self.points:
			res.append(point + offset)
		return res


	# the the value of a cell
	func get_cell(x: int, y: int) -> PixelValue:
		return self.data[x + y * self.size.x]


	# set the value of a cell
	func set_cell(x: int, y: int, v: PixelValue) -> void:
		self.data[x + y * self.size.x] = v
		dirty = true


	# fill all pixels contained inside the shape
	func flood_fill(fill_value: PixelValue = PixelValue.Fill) -> void:
		var W := self.size.x + 2
		var H := self.size.y + 2

		var outside := PackedByteArray()
		outside.resize(W * H)
		outside.fill(0)

		var stack := [Vector2i(-1, -1)]

		while stack.size() > 0:
			var p = stack.pop_back()
			var x = p.x
			var y = p.y

			# Bounds in virtual padded space
			if x < -1 or x > self.size.x or y < -1 or y > self.size.y:
				continue

			var idx = (x + 1) + (y + 1) * W
			if outside[idx] == 1:
				continue

			# If inside real shape AND it's border → cannot pass
			if x >= 0 and x < self.size.x and y >= 0 and y < self.size.y:
				if self.get_cell(x, y) == PixelValue.Border:
					continue

			outside[idx] = 1

			stack.append(Vector2i(x + 1, y))
			stack.append(Vector2i(x - 1, y))
			stack.append(Vector2i(x, y + 1))
			stack.append(Vector2i(x, y - 1))

		# Fill interior (cells not reachable from outside)
		for y in range(self.size.y):
			for x in range(self.size.x):
				if self.get_cell(x, y) == PixelValue.Empty:
					var idx = (x + 1) + (y + 1) * W
					if outside[idx] == 0:
						self.set_cell(x, y, fill_value)


	func thicken(thickness: int) -> void:
		if thickness <= 0:
			return

		# fill with a placeholder value so that we can determine the
		# area inside the shape where the border should expand to
		self.flood_fill(PixelValue.Placeholder)

		var dist = PackedInt32Array()
		dist.resize(self.size.x * self.size.y)
		dist.fill(-1)

		var queue: Array[Vector2i] = []

		# Start BFS from all border cells
		for y in range(self.size.y):
			for x in range(self.size.x):
				if self.get_cell(x, y) == PixelValue.Border:
					var idx = x + y * self.size.x
					dist[idx] = 0
					queue.append(Vector2i(x, y))

		var head = 0

		while head < queue.size():
			var p = queue[head]
			head += 1

			var d = dist[p.x + p.y * self.size.x]
			if d >= thickness:
				continue

			for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx = p.x + off.x
				var ny = p.y + off.y

				if nx < 0 or nx >= self.size.x or ny < 0 or ny >= self.size.y:
					continue

				# Only spread into interior (Fill) cells
				if self.get_cell(nx, ny) != PixelValue.Placeholder:
					continue

				var idx = nx + ny * self.size.x
				if dist[idx] != -1:
					continue

				dist[idx] = d + 1
				queue.append(Vector2i(nx, ny))

		# remove the placeholder values
		self.replace(PixelValue.Empty, PixelValue.Placeholder)

		# Convert interior cells within thickness to border
		for y in range(self.size.y):
			for x in range(self.size.x):
				var d = dist[x + y * self.size.x]
				if d > 0 and d <= thickness:
					set_cell(x, y, PixelValue.Border)


	# clear all pixels in the shape
	func replace(v: PixelValue = PixelValue.Empty, target: PixelValue = PixelValue.All) -> void:
		for y in range(self.size.y):
			for x in range(self.size.x):
				if self.get_cell(x, y) & target:
					self.set_cell(x, y, v)
