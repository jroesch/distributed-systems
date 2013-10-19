package replicatedlog

import scalaz._
import scalaz.effect._
import scalaz.syntax.monad._
import scalaz.Free._
import scalaz.Trampoline._
import scala.tools.jline.console.ConsoleReader
import IO.{ io, putStrLn }

object ReplicatedLog extends SafeApp {
  override def run(args: ImmutableArray[String]) = foreverIO(loop)

  def loop: IO[Unit] = for {
    console <- Console.withPrompt("> ")
    line <- console.readLine
    _ <- putStrLn(line)
  } yield ()


  def foreverIO[A, B >: Nothing](m: IO[A]): IO[B] = m >>= (_ => foreverIO(m))
}

object Console {
  def withPrompt(prompt: String): IO[Console] = IO(Console(prompt))
}

case class Console(prompt: String) {
  private val console = new ConsoleReader()
  console.setPrompt(prompt)

  def readLine: IO[String] = 
    io(rw => done(rw -> { console.readLine() }))
}
    
