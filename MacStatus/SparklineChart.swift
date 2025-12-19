import SwiftUI

struct SparklineChart: View {
    let data: [Double]
    let color: Color
    let maxDataPoints: Int
    
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                guard data.count > 1 else { return }
                
                let width = geometry.size.width
                let height = geometry.size.height
                let stepX = width / CGFloat(maxDataPoints - 1)
                
                // 假设数据范围是 0-100 (百分比)
                let scaleY = height / 100.0
                
                let startX = width - CGFloat(data.count - 1) * stepX
                let startY = height - CGFloat(data[0]) * scaleY
                
                path.move(to: CGPoint(x: startX, y: startY))
                
                for index in 1..<data.count {
                    let x = startX + CGFloat(index) * stepX
                    let y = height - CGFloat(data[index]) * scaleY
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(color, lineWidth: 2)
            
            // 渐变填充背景
            Path { path in
                guard data.count > 1 else { return }
                let width = geometry.size.width
                let height = geometry.size.height
                let stepX = width / CGFloat(maxDataPoints - 1)
                let scaleY = height / 100.0
                let startX = width - CGFloat(data.count - 1) * stepX
                
                path.move(to: CGPoint(x: startX, y: height))
                for index in 0..<data.count {
                    let x = startX + CGFloat(index) * stepX
                    let y = height - CGFloat(data[index]) * scaleY
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.addLine(to: CGPoint(x: width, y: height))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [color.opacity(0.3), color.opacity(0.0)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}

struct SparklineChart_Previews: PreviewProvider {
    static var previews: some View {
        SparklineChart(
            data: [10, 20, 40, 30, 50, 44, 55, 80, 70, 90],
            color: .blue,
            maxDataPoints: 60
        )
        .frame(width: 300, height: 100)
        .padding()
    }
}

